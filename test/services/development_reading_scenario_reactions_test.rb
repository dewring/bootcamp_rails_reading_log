require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioReactionsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @directory = Pathname.new(Dir.mktmpdir("booknook-reactions-"))
    @paths = { snapshot_path: @directory.join("catalog.json"), manifest_path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock") }
    anchors = DevelopmentReadingScenarioReactions::ANCHORS.values.map { |anchor| anchor.fetch("work_key") }
    docs = Array.new(100) do |index|
      { "key" => anchors[index] || "/works/OL#{225_000 + index}W", "title" => "Reaction source #{index}", "author_name" => [ "Source Author" ] }
    end
    stub_request(:get, "https://openlibrary.org/search.json").with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: docs }.to_json)
    in_development do
      snapshot = OpenLibraryCatalogCapture.new(snapshot_path: @paths.fetch(:snapshot_path), lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test").capture_catalog
      DevelopmentReadingScenarioBootstrap.new(**@paths, password: "synthetic-scenario-test-password").bootstrap_scenario
      OpenLibraryCatalogReplay.new(**@paths).replay_catalog
      store = DevelopmentReadingScenarioManifest.new(path: @paths.fetch(:manifest_path), lock_path: @paths.fetch(:lock_path))
      store.with_exclusive_access do
        manifest = store.prepare_scenario(snapshot_id: snapshot.fetch("snapshot_id"))
        # This consumer needs the saved reader/catalog references and completed baseline marker.
        # The coordinator integration tests exercise the complete reading/community baseline.
        manifest["baseline"] = { "status" => "complete" }
        store.save_scenario
      end
    end
    @manifest = saved_manifest
    @reader_ids = (1..30).map { |number| @manifest.dig("bootstrap", "records", "users", format("reader%02d", number), "id") }
    @book_ids = @manifest.dig("catalog", "records").transform_values { |record| record.fetch("book").fetch("id") }
    @service = DevelopmentReadingScenarioReactions.new(**@paths)
    WebMock.reset!
    clear_enqueued_jobs
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "seeding creates exactly 160 owned book reactions with fixed anchors and historical timestamps" do
    before = preserved_rows
    manifest = seed
    section = manifest.fetch("reactions")
    rows = Reaction.where(user_id: @reader_ids)

    assert_equal "complete", section.fetch("status")
    assert_equal({ "book_reactions" => 160, "likes" => 120, "dislikes" => 40 }, section.fetch("actual_counts"))
    assert_equal section.fetch("expected_counts"), section.fetch("actual_counts")
    assert_equal({ "like" => 120, "dislike" => 40 }, rows.group(:kind).count)
    assert_equal 160, rows.count
    assert_equal 160, rows.distinct.count(Arel.sql("(user_id, book_id)"))
    assert_equal @reader_ids.sort, rows.distinct.pluck(:user_id).sort
    assert_equal 160, enqueued_jobs.count { |job| job[:job] == ReactionTotalsJob }
    as_of = Time.iso8601(manifest.fetch("as_of"))
    rows.each do |row|
      assert_operator row.created_at, :>=, as_of - 28.days
      assert_operator row.created_at, :<=, row.updated_at
      assert_operator row.updated_at, :<, as_of
    end
    section.fetch("anchors").each_value do |anchor|
      anchored = rows.where(book_id: anchor.fetch("book_id"))
      assert_equal anchor.fetch("likes"), anchored.where(kind: "like").count
      assert_equal anchor.fetch("dislikes"), anchored.where(kind: "dislike").count
      assert_equal anchor.fetch("recent_likes"), anchored.where(kind: "like", updated_at: as_of - 7.days...as_of).count
      assert anchored.where(kind: "like", updated_at: as_of - 7.days...as_of).all? { |row| row.updated_at == as_of - 1.day }
      assert anchored.where(kind: "like").where("updated_at < ?", as_of - 7.days).all? { |row| row.updated_at == as_of - 10.days }
    end
    others = rows.where.not(book_id: section.fetch("anchors").values.map { |anchor| anchor.fetch("book_id") })
    assert_equal({ "like" => 65, "dislike" => 32 }, others.group(:kind).count)
    assert_equal 95, others.distinct.count(:book_id)
    assert others.where(kind: "like", updated_at: as_of - 7.days...as_of).group(:book_id).count.values.all? { |count| count <= 1 }
    assert_equal before, preserved_rows
    assert_equal 0, ReviewReaction.count
    assert_equal 0, ClubMessageReaction.count
    assert_not_requested :any, /https?:/
  end

  test "replay preserves IDs timestamps and kinds and enqueues no duplicate totals work" do
    first = seed
    before = owned_rows
    clear_enqueued_jobs

    second = seed

    assert_equal before, owned_rows
    assert_equal record_ids(first), record_ids(second)
    assert_equal first.dig("reactions", "anchors"), second.dig("reactions", "anchors")
    assert_no_enqueued_jobs only: ReactionTotalsJob
    assert_not_requested :any, /https?:/
  end

  test "seeded anchors have hand-calculated all-kind scores and shared ranks" do
    manifest = seed
    as_of = Time.iso8601(manifest.fetch("as_of")).in_time_zone
    anchors = manifest.fetch("reactions").fetch("anchors")
    rows = Book.where(id: @book_ids.values).trending(as_of: as_of).to_a

    # Dislikes are all ten days old: recent all-kind totals remain 12, 6, 6, 2.
    assert_equal [ "new_burst", "tie_c", "tie_d", "old_hit" ].map { |name| anchors.fetch(name).fetch("book_id") }, rows.first(4).map(&:id)
    assert_equal [ 12, 6, 6, 2 ], rows.first(4).map(&:trending_score)
    assert_equal [ 1, 2, 2, 4 ], rows.first(4).map(&:trending_rank)
    assert_not_includes rows.map(&:id), anchors.fetch("empty").fetch("book_id")
    assert rows.drop(4).all? { |book| book.trending_score == 1 }
  end

  test "refreshing one old_hit reaction adds one recent contribution without creating rows or changing private activity" do
    seed
    before = owned_rows
    private_rows = preserved_rows
    clear_enqueued_jobs

    result = refresh_old_hit

    action = result.fetch("reactions").fetch(DevelopmentReadingScenarioReactions::REFRESH_ACTION)
    assert_equal "complete", action.fetch("status")
    after = owned_rows
    changed_ids = after.keys.select { |id| before.fetch(id) != after.fetch(id) }
    assert_equal [ action.fetch("reaction_id") ], changed_ids
    row = Reaction.find(action.fetch("reaction_id"))
    assert_equal before.fetch(row.id).except("updated_at"), row.attributes.except("updated_at")
    assert_equal Time.iso8601(result.fetch("as_of")) - 1.day, row.updated_at
    as_of = Time.iso8601(result.fetch("as_of")).in_time_zone
    assert_equal 3, Book.where(id: anchor("old_hit").fetch("book_id")).trending(as_of: as_of).sole.trending_score
    assert_equal private_rows, preserved_rows
    assert_equal 160, owned_rows.length
    assert_no_enqueued_jobs only: ReactionTotalsJob
    assert_not_requested :any, /https?:/
  end

  test "repeating a completed refresh and replaying seeds preserve refreshed rows and action metadata" do
    seed
    first = refresh_old_hit
    rows = owned_rows
    saved = @paths.fetch(:manifest_path).read
    clear_enqueued_jobs

    travel_to(Time.iso8601(first.fetch("as_of")) + 2.days) do
      assert_equal first, refresh_old_hit
    end
    assert_equal saved, @paths.fetch(:manifest_path).read
    replayed = seed
    assert_equal first.dig("reactions", DevelopmentReadingScenarioReactions::REFRESH_ACTION), replayed.dig("reactions", DevelopmentReadingScenarioReactions::REFRESH_ACTION)
    assert_equal rows, owned_rows
    assert_no_enqueued_jobs only: ReactionTotalsJob
  end

  test "an interrupted refresh resumes a committed timestamp without retouching it" do
    seed
    rename = File.method(:rename)
    target_time = Time.iso8601(saved_manifest.fetch("as_of")) - 1.day
    File.stub(:rename, ->(source, destination) {
      changed = Reaction.where(book_id: anchor("old_hit").fetch("book_id"), updated_at: target_time).count == 3
      raise IOError, "Interrupted after refresh commit" if Pathname.new(destination) == @paths.fetch(:manifest_path) && changed

      rename.call(source, destination)
    }) do
      assert_raises(IOError) { refresh_old_hit }
    end
    assert_equal "pending", saved_manifest.dig("reactions", DevelopmentReadingScenarioReactions::REFRESH_ACTION, "status")
    rows = owned_rows

    result = refresh_old_hit

    assert_equal "complete", result.dig("reactions", DevelopmentReadingScenarioReactions::REFRESH_ACTION, "status")
    assert_equal rows, owned_rows
  end

  test "refresh intent saved before a failed database update can resume" do
    seed
    rows = owned_rows
    allow_any_instance_of(Reaction).to receive(:update!).and_raise(ActiveRecord::StatementInvalid, "Interrupted before update")

    assert_raises(ActiveRecord::StatementInvalid) { refresh_old_hit }
    assert_equal rows, owned_rows
    assert_equal "pending", saved_manifest.dig("reactions", DevelopmentReadingScenarioReactions::REFRESH_ACTION, "status")
    RSpec::Mocks.space.reset_all

    assert_equal "complete", refresh_old_hit.dig("reactions", DevelopmentReadingScenarioReactions::REFRESH_ACTION, "status")
  end

  test "a changed refresh plan or changed refreshed row is refused without overwriting it" do
    seed
    result = refresh_old_hit
    action = result.fetch("reactions").fetch(DevelopmentReadingScenarioReactions::REFRESH_ACTION)
    row = Reaction.find(action.fetch("reaction_id"))
    row.update!(kind: "wow")
    saved = @paths.fetch(:manifest_path).read

    assert_raises(DevelopmentReadingScenarioReactions::ReactionsError) { refresh_old_hit }
    assert_equal "wow", row.reload.kind
    assert_equal saved, @paths.fetch(:manifest_path).read

    action["updated_at"] = (Time.iso8601(action.fetch("updated_at")) + 1.hour).iso8601(6)
    write_manifest(result)
    error = assert_raises(DevelopmentReadingScenarioReactions::ReactionsError) { refresh_old_hit }
    assert_includes error.message, "refresh plan changed"
    assert_equal "wow", row.reload.kind
  end

  test "refresh requires completed reaction seeding and refuses production and overlapping operations" do
    saved = @paths.fetch(:manifest_path).read
    assert_raises(DevelopmentReadingScenarioReactions::ReactionsError) { refresh_old_hit }
    assert_equal saved, @paths.fetch(:manifest_path).read
    Rails.stub(:env, "production".inquiry) do
      assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { @service.refresh_old_hit_reaction }
    end
    File.open(@paths.fetch(:lock_path), File::RDWR) do |lock|
      lock.flock(File::LOCK_EX | File::LOCK_NB)
      assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { refresh_old_hit }
    end
    assert_equal saved, @paths.fetch(:manifest_path).read
  end

  test "an interrupted checkpoint resumes the committed reaction without changing it or repeating its callback" do
    rename = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @paths.fetch(:manifest_path) && Reaction.where(user_id: @reader_ids).exists?
        raise IOError, "Interrupted after reaction commit"
      end
      rename.call(source, destination)
    }) do
      assert_raises(IOError) { seed }
    end
    committed = Reaction.where(user_id: @reader_ids).sole
    before = committed.attributes
    assert_nil saved_manifest.dig("reactions", "records").values.first.fetch("id")

    result = seed

    assert_equal before, committed.reload.attributes
    assert_includes record_ids(result).values, committed.id
    assert_equal 160, Reaction.where(user_id: @reader_ids).count
    assert_equal 160, enqueued_jobs.count { |job| job[:job] == ReactionTotalsJob }
  end

  test "a manifest with some checkpointed reactions resumes without replacing saved rows" do
    rename = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      raise IOError, "Interrupted later" if Pathname.new(destination) == @paths.fetch(:manifest_path) && Reaction.where(user_id: @reader_ids).count >= 5

      rename.call(source, destination)
    }) do
      assert_raises(IOError) { seed }
    end
    before = owned_rows
    assert_equal 4, record_ids(saved_manifest).values.compact.length

    result = seed

    before.each { |id, attributes| assert_equal attributes, Reaction.find(id).attributes }
    assert_equal 160, record_ids(result).values.uniq.length
    assert_equal 160, enqueued_jobs.count { |job| job[:job] == ReactionTotalsJob }
  end

  test "unrecorded reactions from synthetic readers stop before any seed or manifest writes" do
    row = Reaction.create!(user_id: @reader_ids.first, book_id: @book_ids.values.first, kind: "love")
    before = @paths.fetch(:manifest_path).read

    assert_no_difference "Reaction.count" do
      error = assert_raises(DevelopmentReadingScenarioReactions::ReactionsError) { seed }
      assert_includes error.message, row.id.to_s
      assert_includes error.message, "no automatic takeover"
    end
    assert_equal before, @paths.fetch(:manifest_path).read
    assert_equal "love", row.reload.kind
  end

  test "changed kind or timestamp and missing owned reactions are refused without repair" do
    seed
    record = Reaction.where(user_id: @reader_ids).first
    original = record.attributes
    record.update!(kind: "love")
    assert_seed_refuses_changes("changed")
    record.update_columns(original.except("id"))
    record.touch(time: record.updated_at + 1.hour)
    assert_seed_refuses_changes("changed")
    record.destroy!
    assert_seed_refuses_changes("missing")
  end

  test "an extra unrecorded pair stops replay without changing existing owned reactions" do
    seed
    pair = Reaction.create!(user_id: @reader_ids.first, book_id: anchor("empty").fetch("book_id"), kind: "wow")

    assert_seed_refuses_changes("Unrecorded")
    assert_equal "wow", pair.reload.kind
  end

  test "real user reactions including other emoji on anchor books remain untouched" do
    real = Reaction.create!(user: users(:leika), book_id: @book_ids.values.first, kind: "love")
    before = real.attributes

    result = seed
    seed

    assert_equal 160, result.dig("reactions", "actual_counts", "book_reactions")
    assert_equal before, real.reload.attributes
    assert_equal 161, Reaction.count
  end

  test "a modified saved plan is refused even if the corresponding row was also edited" do
    result = seed
    identity, record = result.fetch("reactions").fetch("records").first
    record.fetch("expected_attributes")["kind"] = "love"
    Reaction.find(record.fetch("id")).update!(kind: "love")
    write_manifest(result)

    error = assert_raises(DevelopmentReadingScenarioReactions::ReactionsError) { seed }

    assert_includes error.message, "plan or anchors changed"
    assert_equal "love", saved_manifest.dig("reactions", "records", identity, "expected_attributes", "kind")
  end

  test "inactive readers and missing required anchor keys are refused before reaction writes" do
    reader = User.find(@reader_ids.first)
    reader.update!(account_status: "suspended")
    assert_seed_refuses_changes("inactive")
    reader.update!(account_status: "active")
    manifest = saved_manifest
    records = manifest.fetch("catalog").fetch("records")
    records.delete(DevelopmentReadingScenarioReactions::ANCHORS.fetch("empty").fetch("work_key"))
    replacement = Book.create!(title: "Another captured Work", author: "Source Author", ol_work_key: "/works/OL999999999W")
    records[replacement.ol_work_key] = { "book" => { "id" => replacement.id }, "edition" => { "id" => nil } }
    write_manifest(manifest)
    assert_seed_refuses_changes("Required reaction anchors")
  end

  test "tie anchor ID ordering is checked without renumbering or rewriting books" do
    key = DevelopmentReadingScenarioReactions::ANCHORS.fetch("tie_c").fetch("work_key")
    original = Book.find(@book_ids.fetch(key))
    attributes = original.attributes.except("id", "created_at", "updated_at")
    original.destroy!
    replacement = Book.create!(attributes)
    manifest = saved_manifest
    manifest.fetch("catalog").fetch("records").fetch(key).fetch("book")["id"] = replacement.id
    write_manifest(manifest)

    assert_seed_refuses_changes("tie_c.id < tie_d.id")
    assert_equal attributes, replacement.reload.attributes.except("id", "created_at", "updated_at")
  end

  test "validation failure is checkpointed and can resume after the catalog choice is enabled" do
    reaction_types(:like).update!(enabled: false)

    error = assert_raises(ActiveRecord::RecordInvalid) { seed }

    assert_includes error.record.errors[:kind], "is not enabled"
    failed = saved_manifest.fetch("reactions").fetch("records").values.first
    assert_equal "failed", failed.fetch("result")
    assert_equal error.record.errors.full_messages, failed.fetch("errors")
    assert_equal 0, Reaction.where(user_id: @reader_ids).count
    reaction_types(:like).update!(enabled: true)
    assert_equal "complete", seed.dig("reactions", "status")
  end

  test "overlapping scenario operations and non-development environments cannot seed reactions" do
    File.open(@paths.fetch(:lock_path), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX | File::LOCK_NB)
      assert_no_difference "Reaction.count" do
        error = assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { seed }
        assert_includes error.message, "already running"
      end
    end
    [ "test", "production" ].each do |environment|
      Rails.stub(:env, environment.inquiry) do
        assert_no_difference "Reaction.count" do
          assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { @service.seed_reactions }
        end
      end
    end
  end

  test "a pending baseline is refused before the reaction plan is checkpointed" do
    manifest = saved_manifest
    manifest.fetch("baseline")["status"] = "pending"
    write_manifest(manifest)

    assert_seed_refuses_changes("Day 1 baseline")
    assert_not saved_manifest.key?("reactions")
  end

  private

  def in_development(&block)
    Rails.stub(:env, "development".inquiry, &block)
  end

  def seed
    in_development { @service.seed_reactions }
  end

  def refresh_old_hit
    in_development { @service.refresh_old_hit_reaction }
  end

  def saved_manifest
    JSON.parse(@paths.fetch(:manifest_path).read)
  end

  def write_manifest(manifest)
    @paths.fetch(:manifest_path).write(JSON.pretty_generate(manifest))
  end

  def anchor(name)
    saved_manifest.fetch("reactions").fetch("anchors").fetch(name)
  end

  def record_ids(manifest)
    manifest.fetch("reactions").fetch("records").transform_values { |record| record.fetch("id") }
  end

  def owned_rows
    Reaction.where(user_id: @reader_ids).order(:id).to_h { |row| [ row.id, row.attributes ] }
  end

  def preserved_rows
    [ User, Book, ReadingSession, ClubMessage, Review ].to_h { |model| [ model.name, model.order(:id).pluck(:id, :updated_at) ] }
  end

  def assert_seed_refuses_changes(message)
    before = owned_rows
    manifest = @paths.fetch(:manifest_path).read
    clear_enqueued_jobs
    error = assert_raises(DevelopmentReadingScenarioReactions::ReactionsError) { seed }
    assert_includes error.message, message
    assert_equal before, owned_rows
    assert_equal manifest, @paths.fetch(:manifest_path).read
    assert_no_enqueued_jobs only: ReactionTotalsJob
  end
end
