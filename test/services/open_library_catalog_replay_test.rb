require "test_helper"
require "tmpdir"

class OpenLibraryCatalogReplayTest < ActiveSupport::TestCase
  # Commit interruption and cache invalidation checks must cross a real transaction boundary.
  uses_transaction "test_a_committed_subset_resumes_after_interruption_before_its_manifest_update_without_changing_IDs",
    "test_normal_representative_Edition_commit_callbacks_still_invalidate_the_edition_list_cache"

  setup do
    @initial_book_ids = Book.pluck(:id)
    @directory = Pathname.new(Dir.mktmpdir("booknook-catalog-replay-"))
    @snapshot_path = @directory.join("catalog.json")
    @manifest_path = @directory.join("state/reading_scenario.json")
    @lock_path = @directory.join("state/reading_scenario.lock")
    @as_of = Time.zone.local(2026, 10, 30, 12)
    @docs = Array.new(100) do |index|
      number = 153_000 + index
      { "key" => "/works/OL#{number}W", "title" => "Replay source title #{number}", "author_name" => [ "Replay source author #{number}" ] }
    end
    @docs.first.merge!(
      "subject" => [ "Fiction" ], "description" => "Source description", "number_of_pages_median" => 321
    )
    @docs.first(2).each_with_index do |doc, index|
      doc["editions"] = { "docs" => [ {
        "key" => "/books/OL#{153_000 + index}M", "work_key" => [ doc.fetch("key") ],
        "title" => "Representative edition #{index + 1}", "publisher" => [ "Source Publisher" ]
      } ] }
    end
    @replay = build_replay
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "offline replay imports 100 selected Works and only returned representative Editions" do
    snapshot = write_snapshot
    initial_books = Book.count
    initial_editions = BookEdition.count
    initial_genres = BookGenre.count

    manifest = replay_catalog

    assert_equal initial_books + 100, Book.count
    assert_equal initial_editions + 2, BookEdition.count
    assert_equal initial_genres, BookGenre.count
    assert_equal "complete", manifest.fetch("catalog").fetch("status")
    assert_equal({ "books" => 100, "book_editions" => 2 }, manifest.fetch("catalog").fetch("actual_counts"))
    assert_equal 15, manifest.fetch("seed")
    assert_equal @as_of.iso8601(6), manifest.fetch("as_of")
    assert_equal snapshot.fetch("snapshot_id"), manifest.fetch("snapshot_id")
    assert_equal manifest, JSON.parse(@manifest_path.read)
    first = Book.find_by!(ol_work_key: @docs.first.fetch("key"))
    assert_equal 321, first.total_pages
    assert_equal "Source description", first.description
    assert_equal [ "Fiction" ], first.subjects
    assert_nil first.book_editions.first.page_count
    assert_equal({ "field" => "number_of_pages_median", "value" => 321 }, catalog_records(manifest).fetch(first.ol_work_key).fetch("source_page_estimate"))
    assert_equal 98, catalog_records(manifest).values.count { |pair| pair.fetch("edition").fetch("result") == "skipped" }
    assert_not_requested :any, /https?:/
  end

  test "repeating replay preserves IDs and existing record attributes without duplicate rows" do
    write_snapshot
    first = replay_catalog
    books_before = Book.order(:id).map(&:attributes)
    editions_before = BookEdition.order(:id).map(&:attributes)

    second = replay_catalog

    assert_equal recorded_ids(first), recorded_ids(second)
    assert_equal first.dig("catalog", "actual_counts"), second.dig("catalog", "actual_counts")
    assert_equal books_before, Book.order(:id).map(&:attributes)
    assert_equal editions_before, BookEdition.order(:id).map(&:attributes)
    assert catalog_records(second).values.all? { |pair| pair.fetch("book").fetch("result") == "reused" }
    assert_not_requested :any, /https?:/
  end

  test "a snapshot with no returned Editions imports only Works and records all Editions as skipped" do
    @docs.each { |doc| doc.delete("editions") }
    write_snapshot
    manifest = nil

    assert_no_difference "BookEdition.count" do
      manifest = replay_catalog
    end

    assert_equal({ "books" => 100, "book_editions" => 0 }, manifest.fetch("catalog").fetch("actual_counts"))
    assert catalog_records(manifest).values.all? { |pair| pair.fetch("edition").fetch("result") == "skipped" }
    assert_not_requested :any, /https?:/
  end

  test "an existing keyed Book is reused without replacing its catalog metadata" do
    existing = Book.create!(
      ol_work_key: @docs.first.fetch("key"), title: @docs.first.fetch("title"),
      author: @docs.first.fetch("author_name").first, description: "Existing description", total_pages: 456
    )
    before = existing.attributes.except("updated_at")
    write_snapshot

    manifest = replay_catalog

    assert_equal before, existing.reload.attributes.except("updated_at")
    result = catalog_records(manifest).fetch(existing.ol_work_key).fetch("book")
    assert_equal existing.id, result.fetch("id")
    assert_equal "reused", result.fetch("origin")
    assert_equal "reused", result.fetch("result")
    assert_equal 1, existing.book_editions.count
  end

  test "unrelated Books and Editions remain byte-for-byte equivalent in database attributes" do
    unrelated = Book.create!(title: "Unrelated existing book", author: "Another author", description: "Keep this")
    edition = BookEdition.create!(book: unrelated, ol_edition_key: "/books/OL999999M", page_count: 250)
    before = unrelated.reload.attributes
    edition_before = edition.attributes
    write_snapshot

    replay_catalog

    assert_equal before, unrelated.reload.attributes
    assert_equal edition_before, edition.reload.attributes
  end

  test "a collision in the last planned Work stops replay before any database insert or manifest creation" do
    legacy = Book.create!(title: @docs.last.fetch("title"), author: @docs.last.fetch("author_name").first)
    before = legacy.attributes
    write_snapshot

    assert_no_difference [ "Book.count", "BookEdition.count" ] do
      assert_raises(OpenLibraryCatalogPreflight::PreflightError) { replay_catalog }
    end

    assert_equal before, legacy.reload.attributes
    assert_not @manifest_path.exist?
    assert_not_requested :any, /https?:/
  end

  test "a committed subset resumes after interruption before its manifest update without changing IDs" do
    write_snapshot
    original_rename = File.method(:rename)
    renames = 0

    File.stub(:rename, ->(source, destination) {
      renames += 1
      raise IOError, "Interrupted after database commit" if renames == 3

      original_rename.call(source, destination)
    }) do
      assert_raises(IOError) { replay_catalog }
    end

    first_book = Book.find_by!(ol_work_key: @docs.first.fetch("key"))
    second_book = Book.find_by!(ol_work_key: @docs[1].fetch("key"))
    assert first_book.persisted?
    assert_equal 2, BookEdition.where(book_id: [ first_book.id, second_book.id ]).count
    partial = JSON.parse(@manifest_path.read)
    assert_equal first_book.id, catalog_records(partial).fetch(first_book.ol_work_key).fetch("book").fetch("id")
    assert_nil catalog_records(partial).fetch(second_book.ol_work_key).fetch("book").fetch("id")
    ids_before = { first_book.ol_work_key => first_book.id, second_book.ol_work_key => second_book.id }

    complete = replay_catalog

    ids_before.each do |key, id|
      assert_equal id, catalog_records(complete).fetch(key).fetch("book").fetch("id")
    end
    assert_equal 100, Book.where(ol_work_key: @docs.map { |doc| doc.fetch("key") }).count
    assert_equal 2, BookEdition.where(ol_edition_key: [ "/books/OL153000M", "/books/OL153001M" ]).count
    assert_equal recorded_ids(complete), recorded_ids(replay_catalog)
    assert_not_requested :any, /https?:/
  end

  test "the complete intended inventory is persisted before the first Book is saved" do
    write_snapshot
    first_create = Book.method(:create!)
    inspected = false

    Book.stub(:create!, ->(attributes) {
      unless inspected
        manifest = JSON.parse(@manifest_path.read)
        assert_equal 100, catalog_records(manifest).length
        assert catalog_records(manifest).values.all? { |pair| pair.fetch("book").fetch("id").nil? }
        inspected = true
      end
      first_create.call(attributes)
    }) do
      replay_catalog
    end

    assert inspected
  end

  test "a changed recorded row is detected before writing an unfinished later Work" do
    write_snapshot
    interrupt_after_first_work
    changed = Book.find_by!(ol_work_key: @docs.first.fetch("key"))
    changed.update!(description: "An explicit developer edit")
    before = @manifest_path.binread
    rows_before = Book.order(:id).map(&:attributes)

    error = assert_raises(OpenLibraryCatalogReplay::ReplayError) { replay_catalog }

    assert_includes error.message, "changed"
    assert_includes error.message, changed.id.to_s
    assert_equal rows_before, Book.order(:id).map(&:attributes)
    assert_equal before, @manifest_path.binread
    assert_not Book.exists?(ol_work_key: @docs[1].fetch("key"))
  end

  test "a recorded missing Book is not silently recreated on resume" do
    write_snapshot
    interrupt_after_first_work
    missing = Book.find_by!(ol_work_key: @docs.first.fetch("key"))
    missing_id = missing.id
    missing.destroy!

    assert_no_difference [ "Book.count", "BookEdition.count" ] do
      error = assert_raises(OpenLibraryCatalogReplay::ReplayError) { replay_catalog }
      assert_includes error.message, missing_id.to_s
      assert_includes error.message, "no automatic recreation"
    end
  end

  test "a changed recorded Edition is detected before replay mutates any row" do
    write_snapshot
    replay_catalog
    edition = BookEdition.find_by!(ol_edition_key: "/books/OL153000M")
    edition.update!(publisher: "Developer corrected publisher")
    before = @manifest_path.binread

    assert_no_difference [ "Book.count", "BookEdition.count" ] do
      error = assert_raises(OpenLibraryCatalogReplay::ReplayError) { replay_catalog }
      assert_includes error.message, edition.id.to_s
      assert_includes error.message, "changed"
    end
    assert_equal before, @manifest_path.binread
  end

  test "a different snapshot is refused without replacing the original manifest" do
    write_snapshot
    interrupt_after_first_work
    before = @manifest_path.binread
    @docs.last["title"] = "A changed captured title"
    write_snapshot

    assert_no_difference "Book.count" do
      assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { replay_catalog }
    end
    assert_equal before, @manifest_path.binread
  end

  test "a different reference time is refused without importing an unfinished Work" do
    write_snapshot
    interrupt_after_first_work
    before = @manifest_path.binread
    changed_date_replay = build_replay(as_of: @as_of + 1.day)

    assert_no_difference "Book.count" do
      Rails.stub(:env, "development".inquiry) do
        assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { changed_date_replay.replay_catalog }
      end
    end
    assert_equal before, @manifest_path.binread
  end

  test "a manifest for another seed or database is refused before creating an unfinished Work" do
    write_snapshot
    interrupt_after_first_work
    original = JSON.parse(@manifest_path.read)

    { "seed" => 16, "database" => "another_development_database" }.each do |key, value|
      @manifest_path.write(JSON.pretty_generate(original.merge(key => value)))
      before = @manifest_path.binread

      assert_no_difference "Book.count" do
        assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { replay_catalog }
      end
      assert_equal before, @manifest_path.binread
    end
  end

  test "invalid manifest JSON refuses replay without replacing the file or importing records" do
    write_snapshot
    FileUtils.mkdir_p(@manifest_path.dirname)
    @manifest_path.write("not JSON")

    assert_no_difference [ "Book.count", "BookEdition.count" ] do
      error = assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { replay_catalog }
      assert_includes error.message, "manifest contains invalid JSON"
    end

    assert_equal "not JSON", @manifest_path.read
    assert_not_requested :any, /https?:/
  end

  test "future baseline and tick inventory is preserved when catalog replay runs again" do
    write_snapshot
    manifest = replay_catalog
    manifest["baseline"] = { "status" => "complete", "sessions" => { "reader01/session1" => 123 } }
    manifest["ticks"] = { "tick1" => { "session_ids" => [ 456, 457, 458 ] } }
    @manifest_path.write(JSON.pretty_generate(manifest))

    repeated = replay_catalog

    assert_equal manifest.fetch("baseline"), repeated.fetch("baseline")
    assert_equal manifest.fetch("ticks"), repeated.fetch("ticks")
    assert_equal recorded_ids(manifest), recorded_ids(repeated)
  end

  test "normal representative Edition commit callbacks still invalidate the edition list cache" do
    write_snapshot
    deleted_keys = []
    manifest = nil

    Rails.cache.stub(:delete, ->(key, **) { deleted_keys.push(key) }) do
      manifest = replay_catalog
    end

    @docs.first(2).each do |doc|
      id = catalog_records(manifest).fetch(doc.fetch("key")).fetch("book").fetch("id")
      assert_includes deleted_keys, "book:#{id}:editions:list"
    end
  end

  test "normal validation failure rolls back its Work and records a resumable failed result" do
    write_snapshot
    failing_book = Book.new(title: "", author: "")
    failing_book.valid?

    failure = ActiveRecord::RecordInvalid.new(failing_book)
    Book.stub(:create!, ->(*) { raise failure }) do
      error = assert_raises(ActiveRecord::RecordInvalid) { replay_catalog }
      assert_same failure, error
      assert_same failing_book, error.record
    end

    manifest = JSON.parse(@manifest_path.read)
    assert_equal "failed", catalog_records(manifest).fetch(@docs.first.fetch("key")).fetch("book").fetch("result")
    assert_not Book.exists?(ol_work_key: @docs.first.fetch("key"))
    assert_equal "complete", replay_catalog.fetch("catalog").fetch("status")
  end

  test "non-development replay refuses before filesystem writes or HTTP requests" do
    [ "test", "production" ].each do |environment|
      Rails.stub(:env, environment.inquiry) do
        assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { @replay.replay_catalog }
      end
    end

    assert_empty @directory.children
    assert_not_requested :any, /https?:/
  end

  test "overlapping scenario operations refuse before creating a manifest or inserting rows" do
    FileUtils.mkdir_p(@lock_path.dirname)

    File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      assert lock.flock(File::LOCK_EX | File::LOCK_NB)
      assert_no_difference [ "Book.count", "BookEdition.count" ] do
        error = assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { replay_catalog }
        assert_includes error.message, "already running"
      end
    end

    assert_not @manifest_path.exist?
    assert_not_requested :any, /https?:/
  end

  private

  def build_replay(as_of: @as_of)
    OpenLibraryCatalogReplay.new(
      snapshot_path: @snapshot_path, manifest_path: @manifest_path, lock_path: @lock_path, as_of: as_of
    )
  end

  def write_snapshot
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: @docs }.to_json)
    snapshot = Rails.stub(:env, "development".inquiry) do
      OpenLibraryCatalogCapture.new(
        snapshot_path: @snapshot_path, lock_path: @directory.join("capture.lock"),
        contact_email: "contact@example.test"
      ).capture_catalog
    end
    WebMock.reset!
    snapshot
  end

  def replay_catalog
    Rails.stub(:env, "development".inquiry) { @replay.replay_catalog }
  end

  def catalog_records(manifest)
    manifest.fetch("catalog").fetch("records")
  end

  def recorded_ids(manifest)
    catalog_records(manifest).transform_values { |pair| [ pair.fetch("book")["id"], pair.fetch("edition")["id"] ] }
  end

  def interrupt_after_first_work
    original_rename = File.method(:rename)
    renames = 0
    File.stub(:rename, ->(source, destination) {
      renames += 1
      original_rename.call(source, destination)
      raise IOError, "Interrupted after first recorded Work" if renames == 2
    }) do
      assert_raises(IOError) { replay_catalog }
    end
  end
end
