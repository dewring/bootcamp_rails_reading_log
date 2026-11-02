require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioActivityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @initial_user_ids = User.pluck(:id)
    @initial_book_ids = Book.pluck(:id)
    @initial_genres = Genre.all.map(&:attributes)
    @initial_badges = Badge.all.map(&:attributes)
    @directory = Pathname.new(Dir.mktmpdir("booknook-reading-"))
    @paths = { snapshot_path: @directory.join("catalog.json"), manifest_path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock") }
    @activity = DevelopmentReadingScenarioActivity.new(**@paths)
    docs = Array.new(100) do |index|
      { "key" => "/works/OL#{185_000 + index}W", "title" => "Activity source #{index}", "author_name" => [ "Source Author" ], "number_of_pages_median" => index < 50 ? 20 : 1000 }
    end
    stub_request(:get, "https://openlibrary.org/search.json").with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: docs }.to_json)
    in_development do
      OpenLibraryCatalogCapture.new(snapshot_path: @paths.fetch(:snapshot_path), lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test").capture_catalog
      DevelopmentReadingScenarioBootstrap.new(**@paths, password: "synthetic-scenario-test-password").bootstrap_scenario
      OpenLibraryCatalogReplay.new(**@paths).replay_catalog
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @paths.fetch(:snapshot_path)).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog).build_baseline
    end
    WebMock.reset!
    clear_enqueued_jobs
  end

  teardown do
    actor_ids = User.where.not(id: @initial_user_ids).pluck(:id)
    ReadingSession.where(user_id: actor_ids).find_each(&:destroy!)
    User.where(id: actor_ids).find_each(&:destroy!)
    Book.where.not(id: @initial_book_ids).find_each(&:destroy!)
    restore_shared_records(Genre, @initial_genres)
    restore_shared_records(Badge, @initial_badges)
    FileUtils.remove_entry(@directory)
  end

  test "offline replay creates the planned library and dated sessions and preserves callbacks on rerun" do
    original_sessions = ReadingSession.where(user_id: @initial_user_ids).order(:id).map(&:attributes)
    manifest = replay
    reading = manifest.fetch("reading")
    assert_equal "awaiting_jobs", reading.fetch("status")
    assert_equal({ "user_books" => 150, "baseline_reading_sessions" => 300, "reading_sessions" => 300 }, reading.fetch("actual_counts"))
    assert_equal({ "want_to_read" => 54, "finished" => 24, "reading" => 72 }, reading.fetch("state_counts"))
    assert_equal 300, enqueued_jobs.count { |job| job.fetch("job_class") == "BookProgressJob" }
    assert_equal 300, enqueued_jobs.count { |job| job.fetch("job_class") == "BadgeAwardJob" }
    assert_equal 450, enqueued_jobs.count { |job| job.fetch("job_class") == "ChallengeProgressJob" }
    sessions = ReadingSession.where(id: records(manifest, "reading_sessions").values.map { |record| record.fetch("id") })
    assert_equal 28, sessions.distinct.count(:read_on)
    assert sessions.all? { |session| session.notes.start_with?("Synthetic journal.") }
    example = @plan.fetch("page_semantics_example")
    pair = sessions.where(user: User.find_by!(email: "reader07@example.test"), book: Book.find_by!(ol_work_key: example.fetch("work_key")))
    assert_equal 25, pair.sum(:pages_read)
    assert_equal 15, pair.maximum(:pages_read)
    ids = records(manifest, "reading_sessions").transform_values { |record| record.fetch("id") }
    count = enqueued_jobs.length
    second = nil
    assert_no_difference [ "UserBook.count", "ReadingSession.count" ] do
      second = replay
    end
    assert_equal ids, records(second, "reading_sessions").transform_values { |record| record.fetch("id") }
    assert_equal count, enqueued_jobs.length
    assert_equal original_sessions, ReadingSession.where(user_id: @initial_user_ids).order(:id).map(&:attributes)
    assert_not_requested :any, /https?:/
  end

  test "final truth waits for callback jobs and then verifies reconciled library states" do
    replay
    pending = in_development { @activity.reconcile_reading }
    assert_equal "awaiting_jobs", pending.fetch("reading").fetch("status")
    assert_operator pending.dig("reading", "callback_work", "pending_count"), :>, 0
    5.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
    assert_empty enqueued_jobs
    final = in_development { @activity.reconcile_reading }
    assert_equal "complete", final.fetch("reading").fetch("status")
    assert_equal 0, final.dig("reading", "callback_work", "pending_count")
    assert_equal 3, final.dig("reading", "state_counts").length
    assert_operator final.dig("reading", "state_counts", "finished"), :>, 24
  end

  test "validation failure records its reason and can resume after the failure is resolved" do
    invalid = ReadingSession.new
    invalid.errors.add(:pages_read, "must be greater than 0")
    recorder = Object.new
    recorder.define_singleton_method(:record) { invalid }
    ReadingSessionRecorder.stub(:new, recorder) do
      error = assert_raises(DevelopmentReadingScenarioActivity::ActivityError) { replay }
      assert_includes error.message, "failed validation"
    end
    manifest = JSON.parse(@paths.fetch(:manifest_path).read)
    failed = records(manifest, "reading_sessions").values.first
    assert_equal "failed", failed.fetch("result")
    assert_includes failed.fetch("errors").join, "greater than 0"
    assert_equal 0, ReadingSession.where.not(user_id: @initial_user_ids).count
    completed = replay
    assert records(completed, "reading_sessions").values.all? { |record| record.fetch("id") && !record.key?("errors") }
  end

  test "a session committed before checkpoint resumes without inserting or enqueueing it twice" do
    interrupt_after_session_commit
    first = ReadingSession.where.not(user_id: @initial_user_ids).sole
    manifest = JSON.parse(@paths.fetch(:manifest_path).read)
    assert records(manifest, "reading_sessions").values.all? { |record| record.fetch("id").nil? }
    completed = replay
    assert_includes records(completed, "reading_sessions").values.map { |record| record.fetch("id") }, first.id
    assert_equal 300, ReadingSession.where.not(user_id: @initial_user_ids).count
    assert_equal 300, enqueued_jobs.count { |job| job.fetch("job_class") == "BookProgressJob" }
  end

  test "ambiguous committed sessions are reported without choosing or deleting either row" do
    interrupt_after_session_commit
    first = ReadingSession.where.not(user_id: @initial_user_ids).sole
    duplicate = ReadingSession.create!(first.attributes.except("id", "created_at", "updated_at"))
    assert_no_difference [ "UserBook.count", "ReadingSession.count" ] do
      error = assert_raises(DevelopmentReadingScenarioActivity::ActivityError) { replay }
      assert_includes error.message, "Ambiguous"
      assert_includes error.message, first.id.to_s
      assert_includes error.message, duplicate.id.to_s
    end
  end

  test "a deleted recorded session is refused rather than recreated" do
    manifest = replay
    id = records(manifest, "reading_sessions").values.first.fetch("id")
    ReadingSession.find(id).destroy!
    assert_no_difference [ "UserBook.count", "ReadingSession.count" ] do
      error = assert_raises(DevelopmentReadingScenarioActivity::ActivityError) { replay }
      assert_includes error.message, id.to_s
      assert_includes error.message, "missing"
    end
  end

  test "baseline replay retains additional sessions owned by a recorded tick" do
    manifest = replay
    reader = User.find_by!(email: "reader08@example.test")
    library = reader.user_books.find_by!(status: "reading")
    tick_sessions = Array.new(3) do |index|
      ReadingSession.create!(user: reader, book: library.book, read_on: Date.new(2026, 10, 30), pages_read: index + 1, notes: "Synthetic follow-up reading #{index + 1}.")
    end
    manifest["ticks"] = { "first_tick" => { "reading_sessions" => tick_sessions.each_with_index.to_h do |session, index|
      [ "session#{index + 1}", { "id" => session.id, "expected_attributes" => JSON.parse(session.attributes.except("id", "updated_at").to_json) } ]
    end } }
    @paths.fetch(:manifest_path).write(JSON.generate(manifest))
    result = nil
    assert_no_difference [ "UserBook.count", "ReadingSession.count" ] do
      result = replay
    end
    assert_equal 303, result.dig("reading", "actual_counts", "reading_sessions")
    assert_equal manifest.fetch("ticks"), result.fetch("ticks")
    assert tick_sessions.all? { |session| ReadingSession.exists?(session.id) }
  end

  test "an edited recorded session is refused before any replay writes" do
    manifest = replay
    id = records(manifest, "reading_sessions").values.last.fetch("id")
    ReadingSession.find(id).update!(notes: "User edited journal")
    assert_no_difference [ "UserBook.count", "ReadingSession.count" ] do
      error = assert_raises(DevelopmentReadingScenarioActivity::ActivityError) { replay }
      assert_includes error.message, id.to_s
      assert_includes error.message, "changed"
    end
    assert_equal "User edited journal", ReadingSession.find(id).notes
  end

  test "unrecorded reading activity on a synthetic account is refused before baseline writes" do
    user = User.find_by!(email: "reader01@example.test")
    book = Book.find_by!(ol_work_key: @plan.fetch("user_books").first.fetch("work_key"))
    session = ReadingSession.create!(user: user, book: book, read_on: Date.current, pages_read: 3)
    assert_no_difference [ "UserBook.count", "ReadingSession.count" ] do
      error = assert_raises(DevelopmentReadingScenarioActivity::ActivityError) { replay }
      assert_includes error.message, session.id.to_s
      assert_includes error.message, "Unrecorded"
    end
  end

  test "non-development replay refuses before creating reading rows" do
    assert_no_difference [ "UserBook.count", "ReadingSession.count" ] do
      assert_raises(DevelopmentReadingScenarioActivity::ActivityError) { @activity.replay_reading }
    end
  end

  private

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def in_development(&block)
    Rails.stub(:env, "development".inquiry, &block)
  end

  def replay
    in_development { @activity.replay_reading }
  end

  def records(manifest, group)
    manifest.fetch("reading").fetch("records").fetch(group)
  end

  def interrupt_after_session_commit
    original_rename = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @paths.fetch(:manifest_path) && ReadingSession.where.not(user_id: @initial_user_ids).exists?
        raise IOError, "Interrupted after session commit"
      end
      original_rename.call(source, destination)
    }) do
      assert_raises(IOError) { replay }
    end
  end

  def restore_shared_records(model, originals)
    model.where.not(id: originals.map { |attributes| attributes.fetch("id") }).find_each(&:destroy!)
    originals.each do |attributes|
      existing = model.find_by(id: attributes.fetch("id"))
      existing ? existing.update!(attributes.except("id")) : model.create!(attributes)
    end
  end
end
