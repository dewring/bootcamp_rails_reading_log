require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @initial_users = User.pluck(:id)
    @initial_books = Book.pluck(:id)
    @initial_clubs = BookClub.pluck(:id)
    @directory = Pathname.new(Dir.mktmpdir("booknook-baseline-"))
    @paths = { snapshot_path: @directory.join("catalog.json"), manifest_path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock") }
    @scenario = DevelopmentReadingScenario.new(**@paths, password: "synthetic-scenario-test-password")
    docs = Array.new(100) do |index|
      key = DevelopmentReadingScenarioReactions::ANCHORS.values.map { |anchor| anchor.fetch("work_key") }[index] || "/works/OL#{205_000 + index}W"
      { "key" => key, "title" => "Baseline source #{index}", "author_name" => [ "Source Author" ], "number_of_pages_median" => 1000 }
    end
    stub_request(:get, "https://openlibrary.org/search.json").with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: docs }.to_json)
    in_development do
      OpenLibraryCatalogCapture.new(snapshot_path: @paths.fetch(:snapshot_path), lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test").capture_catalog
    end
    WebMock.reset!
    clear_enqueued_jobs
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "the seed entry point creates the complete offline baseline while callbacks remain queued" do
    output, = capture_io do
      DevelopmentReadingScenario.stub(:new, @scenario) do
        in_development { load Rails.root.join("db/seeds.rb") }
      end
    end
    manifest = JSON.parse(@paths.fetch(:manifest_path).read)
    baseline = manifest.fetch("baseline")
    assert_equal({ "books" => 100, "book_editions" => 0, "users" => 31, "user_books" => 150, "reading_sessions" => 300,
      "book_clubs" => 4, "book_club_memberships" => 24, "club_messages" => 80, "reviews" => 20 }, baseline.fetch("actual_counts"))
    assert_equal baseline.fetch("expected_counts"), baseline.fetch("actual_counts")
    assert_equal "complete", baseline.fetch("status")
    assert_includes output, "complete"
    assert_equal DevelopmentReadingScenarioReactions::COUNTS, manifest.dig("reactions", "actual_counts")
    assert_not manifest.fetch("reading").key?("callback_work")
    assert_not_empty enqueued_jobs
    assert_equal 12, manifest.dig("bootstrap", "actual_counts", "genres")
    assert_equal 5, manifest.dig("bootstrap", "actual_counts", "badges")
    actors = manifest.dig("bootstrap", "records", "users").values.map { |record| record.fetch("id") }
    assert_equal 160, Reaction.where(user_id: actors).count
    assert_equal 28, ReadingSession.where(user_id: actors).distinct.count(:read_on)
    assert_equal 3, UserBook.where(user_id: actors).distinct.count(:status)
    assert_equal 0, WebhookEndpoint.where(user_id: actors).count
    assert_equal 0, enqueued_jobs.count { |job| job.fetch("job_class") == "CoverAttachJob" }
    assert_not_requested :any, /https?:/
  end

  test "one baseline command saves users books and shelves before reading sessions and community records" do
    observed = {}
    recorder_factory = ReadingSessionRecorder.method(:new)
    club_factory = BookClubCreator.method(:new)
    reading = ->(*arguments) {
      observed[:before_reading] ||= {
        users: User.where.not(id: @initial_users).count,
        books: Book.where.not(id: @initial_books).count,
        shelves: UserBook.where(user_id: User.where.not(id: @initial_users).select(:id)).count
      }
      recorder_factory.call(*arguments)
    }
    community = ->(**arguments) {
      observed[:before_community] ||= ReadingSession.where(user_id: User.where.not(id: @initial_users).select(:id)).count
      club_factory.call(**arguments)
    }

    ReadingSessionRecorder.stub(:new, reading) do
      BookClubCreator.stub(:new, community) { seed }
    end

    assert_equal({ users: 31, books: 100, shelves: 150 }, observed.fetch(:before_reading))
    assert_equal 300, observed.fetch(:before_community)
    assert_equal 4, BookClub.where.not(id: @initial_clubs).count
    assert_not_requested :any, /https?:/
  end

  test "the complete scenario seeds reactions only after the Day 1 reading and community records" do
    factory = Reaction.method(:create!)
    observed = nil
    create = ->(attributes) {
      observed ||= {
        users: User.where.not(id: @initial_users).count,
        books: Book.where.not(id: @initial_books).count,
        sessions: ReadingSession.where.not(user_id: @initial_users).count,
        posts: ClubMessage.where(user_id: User.where.not(id: @initial_users).select(:id)).count
      }
      factory.call(attributes)
    }

    result = Reaction.stub(:create!, create) { in_development { @scenario.seed_scenario } }

    assert_equal({ users: 31, books: 100, sessions: 300, posts: 80 }, observed)
    assert_equal DevelopmentReadingScenarioReactions::COUNTS, result.dig("reactions", "actual_counts")
    assert_not_requested :any, /https?:/
  end

  test "reaction seeding after the existing tick preserves 303 sessions and 82 posts" do
    seed
    in_development { DevelopmentReadingScenarioTick.new(**@paths).advance_scenario(tick: "tick1") }
    sessions = ReadingSession.order(:id).map(&:attributes)
    posts = ClubMessage.order(:id).map(&:attributes)

    result = in_development { @scenario.seed_scenario }

    assert_equal 303, result.dig("baseline", "actual_counts", "reading_sessions")
    assert_equal 82, result.dig("baseline", "actual_counts", "club_messages")
    assert_equal sessions, ReadingSession.order(:id).map(&:attributes)
    assert_equal posts, ClubMessage.order(:id).map(&:attributes)
    assert_equal DevelopmentReadingScenarioReactions::COUNTS, result.dig("reactions", "actual_counts")
  end

  test "baseline preflight rejects an edited synthetic user before any phase writes" do
    seed
    user = User.find_by!(email: "reader30@example.test")
    user.update!(first_name: "Changed by the reader")

    assert_no_difference model_counts do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { seed }
      assert_includes error.message, user.id.to_s
      assert_includes error.message, "changed"
    end
    assert_equal "Changed by the reader", user.reload.first_name
    assert_not_requested :any, /https?:/
  end

  test "baseline preflight rejects an edited book before any phase writes" do
    manifest = seed
    book = Book.find(manifest.fetch("catalog").fetch("records").values.first.fetch("book").fetch("id"))
    pages = book.total_pages + 1
    book.update!(total_pages: pages)

    assert_no_difference model_counts do
      error = assert_raises(OpenLibraryCatalogReplay::ReplayError) { seed }
      assert_includes error.message, book.id.to_s
      assert_includes error.message, "changed"
    end
    assert_equal pages, book.reload.total_pages
    assert_not_requested :any, /https?:/
  end

  test "after normal jobs drain replay reports complete without duplicating records or queue work" do
    first = seed
    ids = selected_ids(first)
    originals = User.where(id: @initial_users).order(:id).map(&:attributes)
    5.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
    assert_empty enqueued_jobs
    result = nil
    assert_no_difference model_counts do
      result = seed
    end
    assert_equal "complete", result.dig("baseline", "status")
    assert_equal first.dig("baseline", "actual_counts"), result.dig("baseline", "actual_counts")
    assert_equal ids, selected_ids(result)
    assert_empty enqueued_jobs
    assert_equal originals, User.where(id: @initial_users).order(:id).map(&:attributes)
    assert_not_requested :any, /https?:/
  end

  test "a fresh club collision is reported before any baseline records are inserted" do
    club = BookClub.create!(name: "Reading Scenario Recent Readers")
    assert_no_difference model_counts do
      error = assert_raises(DevelopmentReadingScenario::ScenarioError) { seed }
      assert_includes error.message, club.id.to_s
      assert_includes error.message, "club-name collisions"
    end
    assert_not @paths.fetch(:manifest_path).exist?
    assert_empty enqueued_jobs
  end

  test "a synthetic identity collision is reported before books genres or badges are inserted" do
    existing = User.create!(first_name: "Real", last_name: "Reader", nickname: "existing_reader", email: "reader30@example.test", password: "existing-test-password")
    attributes = existing.attributes
    assert_no_difference model_counts do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { seed }
      assert_includes error.message, existing.id.to_s
    end
    assert_equal attributes, existing.reload.attributes
    assert_not @paths.fetch(:manifest_path).exist?
  end

  test "missing credentials fail before catalog or account writes" do
    scenario = DevelopmentReadingScenario.new(**@paths, password: nil)
    assert_no_difference model_counts do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { in_development { scenario.seed_baseline } }
      assert_includes error.message, "DEVELOPMENT_SCENARIO_PASSWORD"
    end
    assert_not @paths.fetch(:manifest_path).exist?
  end

  test "the complete baseline resumes after a session commit preceding its checkpoint" do
    original = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @paths.fetch(:manifest_path) && ReadingSession.where.not(user_id: @initial_users).exists?
        raise IOError, "Interrupted after session commit"
      end
      original.call(source, destination)
    }) do
      assert_raises(IOError) { seed }
    end
    session = ReadingSession.where.not(user_id: @initial_users).sole
    assert_equal 0, BookClub.where.not(id: @initial_clubs).count
    assert_equal 0, ClubMessage.where(user_id: User.where.not(id: @initial_users).select(:id)).count
    completed = seed
    assert_includes completed.dig("reading", "records", "reading_sessions").values.map { |record| record.fetch("id") }, session.id
    assert_equal 300, completed.dig("baseline", "actual_counts", "reading_sessions")
    assert_equal 80, completed.dig("baseline", "actual_counts", "club_messages")
    assert_equal 300, enqueued_jobs.count { |job| job.fetch("job_class") == "BookProgressJob" }
  end

  test "late recorded drift fails preflight without changing database rows or the saved manifest" do
    manifest = seed
    review_id = manifest.dig("community", "records", "reviews").values.last.fetch("id")
    Review.find(review_id).update!(body: "A reader revised this review")
    saved = @paths.fetch(:manifest_path).read
    queue = enqueued_jobs.dup
    assert_no_difference model_counts do
      error = assert_raises(DevelopmentReadingScenarioCommunity::CommunityError) { seed }
      assert_includes error.message, review_id.to_s
      assert_includes error.message, "changed"
    end
    assert_equal saved, @paths.fetch(:manifest_path).read
    assert_equal queue, enqueued_jobs
    assert_equal "A reader revised this review", Review.find(review_id).body
  end

  test "an overlapping run is refused before baseline writes" do
    File.open(@paths.fetch(:lock_path), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX | File::LOCK_NB)
      assert_no_difference model_counts do
        error = assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { seed }
        assert_includes error.message, "already running"
      end
    end
    assert_not @paths.fetch(:manifest_path).exist?
  end

  test "a missing snapshot does not trigger capture or fall back to static books" do
    File.rename(@paths.fetch(:snapshot_path), @directory.join("original.json"))
    assert_no_difference model_counts do
      error = assert_raises(OpenLibraryCatalogPreflight::PreflightError) { seed }
      assert_includes error.message, "Snapshot is missing"
    end
    assert_not_requested :any, /https?:/
  end

  test "baseline errors retain the original exception object diagnostic report and origin" do
    expected = OpenLibraryCatalogPreflight::PreflightError.new("Unable to read captured catalog", report: { "source" => "catalog snapshot" })
    preflight = Object.new
    preflight.define_singleton_method(:preflight_catalog) { raise expected }

    OpenLibraryCatalogPreflight.stub(:new, preflight) do
      assert_no_difference model_counts do
        actual = assert_raises(OpenLibraryCatalogPreflight::PreflightError) { seed }
        assert_same expected, actual
        assert_equal({ "source" => "catalog snapshot" }, actual.report)
        assert_includes actual.backtrace.first, __FILE__
      end
    end
  end

  test "the seed entry point refuses non-development environments before writes or HTTP" do
    [ "test", "production" ].each do |environment|
      assert_no_difference model_counts do
        Rails.stub(:env, environment.inquiry) do
          assert_raises(DevelopmentReadingScenario::ScenarioError) { load Rails.root.join("db/seeds.rb") }
          assert_raises(DevelopmentReadingScenario::ScenarioError) { @scenario.seed_baseline }
        end
      end
    end
    assert_not @paths.fetch(:manifest_path).exist?
    assert_empty enqueued_jobs
    assert_not_requested :any, /https?:/
  end

  private

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def in_development(&block)
    Rails.stub(:env, "development".inquiry, &block)
  end

  def seed
    in_development { @scenario.seed_baseline }
  end

  def model_counts
    [ "Genre.count", "Badge.count", "User.count", "Book.count", "BookEdition.count", "UserBook.count", "ReadingSession.count", "BookClub.count", "BookClubMembership.count", "ClubMessage.count", "Review.count" ]
  end

  def selected_ids(manifest)
    [ "bootstrap", "catalog", "reading", "community" ].to_h do |section|
      records = manifest.fetch(section).fetch("records")
      ids = records.transform_values do |group|
        selected = section == "catalog" ? group.slice("book", "edition") : group
        selected.transform_values { |record| record["id"] }
      end
      [ section, ids ]
    end
  end
end
