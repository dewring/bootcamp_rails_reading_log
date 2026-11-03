require "test_helper"
require "tmpdir"

class OpenLibraryCatalogPreflightTest < ActiveSupport::TestCase
  setup do
    @directory = Pathname.new(Dir.mktmpdir("booknook-catalog-preflight-"))
    @snapshot_path = @directory.join("catalog.json")
    @docs = Array.new(100) do |index|
      number = 142_000 + index
      { "key" => "/works/OL#{number}W", "title" => "Source title #{number}", "author_name" => [ "Source author #{number}" ] }
    end
    @docs.first.merge!(
      "title" => "eBooks and EPUB: a reader's guide",
      "author_name" => [ "Gabriel García Márquez", "Another source author" ],
      "description" => { "value" => "A description from the source." },
      "subject" => [ "Fiction", "Libraries" ],
      "number_of_pages_median" => 321,
      "isbn" => [ "unrelated-work-isbn" ],
      "publisher" => [ "Unrelated Work Publisher" ],
      "editions" => { "docs" => [ {
        "key" => "/books/OL142000M", "work_key" => [ "/works/OL142000W" ],
        "title" => "The representative edition", "isbn" => [ "9780140449136" ],
        "publisher" => [ "Source Edition Publisher" ], "publish_date" => [ "2002" ],
        "language" => [ "eng" ], "format" => [ "Paperback" ]
      } ] }
    )
    @manifest_path = @directory.join("manifest.json")
    @preflight = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path, manifest_path: @manifest_path)
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "preflight maps 100 Works offline without creating records or changing the snapshot" do
    snapshot = write_snapshot
    before = @snapshot_path.binread
    report = nil

    assert_no_difference [ "Book.count", "BookEdition.count", "BookGenre.count" ] do
      report = preflight_catalog
    end

    assert_equal snapshot.fetch("snapshot_id"), report.fetch("snapshot_id")
    assert_equal 100, report.fetch("books").length
    assert_empty report.fetch("conflicts")
    book = report.fetch("books").first
    assert_equal @docs.first.fetch("title"), book.fetch("book_attributes").fetch("title")
    assert_equal "Gabriel García Márquez", book.fetch("book_attributes").fetch("author")
    assert_equal "A description from the source.", book.fetch("book_attributes").fetch("description")
    assert_equal [ "Fiction", "Libraries" ], book.fetch("book_attributes").fetch("subjects")
    assert_equal 321, book.fetch("book_attributes").fetch("total_pages")
    assert_equal "number_of_pages_median", book.fetch("page_estimate_source")
    assert_equal "pending", book.fetch("book_status")
    assert_equal before, @snapshot_path.binread
    assert_not_requested :any, /https?:/
  end

  test "representative edition attributes come only from the first nested edition" do
    @docs.first.fetch("editions").fetch("docs").push({
      "key" => "/books/OL142001M", "isbn" => [ "unrelated-second-edition-isbn" ],
      "publisher" => [ "Unrelated Second Edition Publisher" ]
    })
    write_snapshot

    edition = preflight_catalog.fetch("books").first.fetch("edition_attributes")

    assert_equal({
      "ol_edition_key" => "/books/OL142000M", "title" => "The representative edition",
      "isbn" => "9780140449136", "publisher" => "Source Edition Publisher", "publish_year" => "2002",
      "language" => "eng", "format" => "Paperback", "page_count" => nil
    }, edition)
    assert_not_requested :any, /https?:/
  end

  test "missing optional Work and Edition metadata stays nil without Work-array fallbacks" do
    @docs.first.delete("description")
    @docs.first.delete("subject")
    @docs.first.delete("number_of_pages_median")
    @docs.first["editions"] = { "docs" => [ { "key" => "/books/OL142000M" } ] }
    write_snapshot

    book = preflight_catalog.fetch("books").first

    assert_nil book.fetch("book_attributes").fetch("description")
    assert_nil book.fetch("book_attributes").fetch("subjects")
    assert_nil book.fetch("book_attributes").fetch("total_pages")
    assert_nil book.fetch("page_estimate_source")
    assert_equal [ "description", "subjects", "total_pages" ], book.fetch("missing_optional_fields")
    assert_nil book.fetch("edition_attributes").fetch("isbn")
    assert_nil book.fetch("edition_attributes").fetch("publisher")
    assert_nil book.fetch("edition_attributes").fetch("title")
    assert_nil book.fetch("edition_attributes").fetch("page_count")
  end

  test "a Work with no returned edition is reported as skipped without an invented edition" do
    write_snapshot

    book = preflight_catalog.fetch("books")[1]

    assert_nil book.fetch("edition_attributes")
    assert_equal "skipped", book.fetch("edition_status")
  end

  test "nonpositive or nonnumeric Work page medians are not treated as page totals" do
    @docs.first["number_of_pages_median"] = 0
    @docs[1]["number_of_pages_median"] = "250"
    @docs[2]["number_of_pages_median"] = -10
    write_snapshot

    preflight_catalog.fetch("books").first(3).each do |book|
      assert_nil book.fetch("book_attributes").fetch("total_pages")
      assert_nil book.fetch("page_estimate_source")
    end
  end

  test "preflight normalizes bare external keys while retaining the raw source file" do
    @docs.first["key"] = "OL142000W"
    @docs.first.fetch("editions").fetch("docs").first["key"] = "OL142000M"
    write_snapshot
    before = @snapshot_path.binread

    book = preflight_catalog.fetch("books").first

    assert_equal "/works/OL142000W", book.fetch("book_attributes").fetch("ol_work_key")
    assert_equal "/books/OL142000M", book.fetch("edition_attributes").fetch("ol_edition_key")
    assert_equal before, @snapshot_path.binread
  end

  test "an exact keyed Book and its Edition are marked for reuse without changing unrelated attributes" do
    book = create_selected_book(description: "Existing catalog description", total_pages: 123)
    edition = BookEdition.create!(book: book, ol_edition_key: "/books/OL142000M", publisher: "Existing Publisher", page_count: 120)
    book_before = book.reload.attributes
    edition_before = edition.attributes
    write_snapshot

    result = preflight_catalog.fetch("books").first

    assert_equal book.id, result.fetch("existing_book_id")
    assert_equal edition.id, result.fetch("existing_edition_id")
    assert_equal "reused", result.fetch("book_status")
    assert_equal "reused", result.fetch("edition_status")
    assert_equal book_before, book.reload.attributes
    assert_equal edition_before, edition.reload.attributes
    assert_not_requested :any, /https?:/
  end

  test "a legacy unkeyed book is reported by ID without adding a duplicate or assigning its key" do
    legacy = Book.create!(title: @docs.first.fetch("title").titleize, author: "Gabriel García Márquez".titleize)
    before = legacy.attributes
    write_snapshot

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "legacy_unkeyed_book" }
    assert_equal [ legacy.id ], conflict.fetch("record_ids")
    assert_includes conflict.fetch("next_step"), "No automatic merge or overwrite"
    assert_equal before, legacy.reload.attributes
  end

  test "an unkeyed collision in the last selected Work is detected before any earlier import" do
    @docs.last["title"] = books(:refactoring).title
    @docs.last["author_name"] = [ books(:refactoring).author ]
    write_snapshot

    error = assert_read_only_failure

    assert_equal [ books(:refactoring).id ], error.report.fetch("conflicts").first.fetch("record_ids")
    assert_equal "/works/OL142099W", error.report.fetch("conflicts").first.fetch("work_key")
  end

  test "the same title and author with a different existing Work key requires review" do
    book = create_selected_book(ol_work_key: "/works/OL999999W")
    write_snapshot

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "different_work_key" }
    assert_equal [ book.id ], conflict.fetch("record_ids")
  end

  test "distinct selected Works with identical titles and authors can each reuse their own keyed Book" do
    @docs[1]["title"] = @docs.first.fetch("title")
    @docs[1]["author_name"] = @docs.first.fetch("author_name")
    first_book = create_selected_book
    second_book = create_selected_book(ol_work_key: "/works/OL142001W")
    write_snapshot

    report = preflight_catalog

    assert_empty report.fetch("conflicts")
    assert_equal [ first_book.id, second_book.id ], report.fetch("books").first(2).map { |entry| entry.fetch("existing_book_id") }
    assert_equal [ "reused", "reused" ], report.fetch("books").first(2).map { |entry| entry.fetch("book_status") }
  end

  test "an existing Work key attached to a different title or author requires review" do
    book = create_selected_book(title: "A different existing title", author: "A different existing author")
    write_snapshot

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "conflicting_work_identity" }
    assert_equal [ book.id ], conflict.fetch("record_ids")
  end

  test "canonical and bare existing keys for the same Work are ambiguous" do
    canonical = create_selected_book
    bare = create_selected_book(ol_work_key: "OL142000W")
    write_snapshot

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "ambiguous_work_identity" }
    assert_equal [ canonical.id, bare.id ].sort, conflict.fetch("record_ids").sort
  end

  test "a whitespace-padded existing Work key is reported instead of creating a canonical duplicate" do
    book = create_selected_book(ol_work_key: " /works/OL142000W ", title: "A different title")
    write_snapshot

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "conflicting_work_identity" }
    assert_equal [ book.id ], conflict.fetch("record_ids")
  end

  test "an existing Edition belonging to another Book is reported without reassignment" do
    edition = BookEdition.create!(book: books(:pragmatic), ol_edition_key: "/books/OL142000M")
    before = edition.attributes
    write_snapshot

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "conflicting_edition_identity" }
    assert_equal [ edition.id ], conflict.fetch("record_ids")
    assert_equal [ books(:pragmatic).id ], conflict.fetch("book_ids")
    assert_equal before, edition.reload.attributes
  end

  test "a returned representative Edition that names another Work is rejected" do
    @docs.first.fetch("editions").fetch("docs").first["work_key"] = [ "/works/OL999999W" ]
    write_snapshot

    error = assert_read_only_failure

    assert_equal "edition_work_mismatch", error.report.fetch("conflicts").first.fetch("reason")
  end

  test "one representative Edition selected under two Works is reported before import" do
    @docs[1]["editions"] = { "docs" => [ { "key" => "/books/OL142000M" } ] }
    write_snapshot

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "edition_selected_for_multiple_works" }
    assert_equal [ "/works/OL142000W", "/works/OL142001W" ], conflict.fetch("work_keys")
  end

  test "source edits after capture are rejected before database writes" do
    snapshot = write_snapshot
    snapshot.fetch("pages").first["raw_body"] = '{"docs":[]}'
    @snapshot_path.write(JSON.generate(snapshot))

    error = assert_read_only_failure

    assert_includes error.message, "checksum does not match"
  end

  test "a reordered selection is rejected even when source responses are unchanged" do
    snapshot = write_snapshot
    snapshot.fetch("selected").reverse!
    @snapshot_path.write(JSON.generate(snapshot))

    error = assert_read_only_failure

    assert_includes error.message, "first 100 valid distinct Works in source order"
  end

  test "an incomplete snapshot cannot produce a partial import plan" do
    snapshot = write_snapshot
    snapshot.fetch("selected").pop
    @snapshot_path.write(JSON.generate(snapshot))

    assert_read_only_failure
  end

  test "a missing snapshot reports the capture command without making HTTP requests" do
    error = assert_read_only_failure

    assert_includes error.message, "development_scenario:capture_catalog"
  end

  test "invalid snapshot JSON fails without making HTTP requests or database writes" do
    @snapshot_path.write("not JSON")

    error = assert_read_only_failure

    assert_includes error.message, "invalid JSON"
  end

  test "non-development preflight refuses before reading a snapshot or making HTTP requests" do
    [ "test", "production" ].each do |environment|
      Rails.stub(:env, environment.inquiry) do
        error = assert_raises(OpenLibraryCatalogPreflight::PreflightError) { @preflight.preflight_catalog }
        assert_includes error.message, "only available in development"
      end
    end

    assert_empty @directory.children
    assert_not_requested :any, /https?:/
  end

  test "a reviewed keyed identity reuses its existing metadata and preserves a reviewed legacy duplicate" do
    book = create_selected_book(author: "Gabriel García Márquez.", total_pages: 123)
    legacy = Book.create!(title: @docs.first.fetch("title"), author: "Gabriel García Márquez")
    write_review(book, preserved: [ legacy ])
    before = [ book.attributes, legacy.attributes ]

    assert_no_difference [ "Book.count", "BookEdition.count" ] do
      result = preflight_catalog.fetch("books").first
      assert_equal book.id, result.fetch("existing_book_id")
      assert_equal "reused", result.fetch("book_status")
    end

    assert_equal before, [ book.reload.attributes, legacy.reload.attributes ]
    assert_not_requested :any, /https?:/
  end

  test "a reviewed identity does not authorize later changes to the keyed book" do
    book = create_selected_book(author: "Reviewed author.")
    write_review(book)
    book.update!(author: "A later unrelated author")

    error = assert_read_only_failure

    assert_includes error.report.fetch("conflicts").map { |entry| entry.fetch("reason") }, "conflicting_work_identity"
  end

  test "reviewed identities from another database or snapshot do not authorize reuse" do
    book = create_selected_book(author: "Reviewed author.")

    [ "database", "snapshot_id" ].each do |field|
      write_review(book)
      manifest = JSON.parse(@manifest_path.read)
      manifest[field] = "another-#{field}"
      @manifest_path.write(manifest.to_json)

      assert_read_only_failure
    end
  end

  test "a review does not authorize a different source identity or a different target record" do
    book = create_selected_book(author: "Reviewed author.")

    [ "source", "target" ].each do |field|
      write_review(book)
      manifest = JSON.parse(@manifest_path.read)
      manifest.dig("catalog", "reviewed_identities", @docs.first.fetch("key"), field)["title"] = "Another title"
      @manifest_path.write(manifest.to_json)

      assert_read_only_failure
    end
  end

  test "reviewing one legacy duplicate does not hide a newly added legacy collision" do
    book = create_selected_book
    legacy = Book.create!(title: @docs.first.fetch("title"), author: "Gabriel García Márquez")
    write_review(book, preserved: [ legacy ])
    unreviewed = Book.create!(title: legacy.title, author: legacy.author)

    error = assert_read_only_failure

    conflict = error.report.fetch("conflicts").find { |entry| entry.fetch("reason") == "legacy_unkeyed_book" }
    assert_equal [ unreviewed.id ], conflict.fetch("record_ids")
  end

  private

  def write_review(book, preserved: [])
    snapshot = write_snapshot
    source = @docs.first
    @manifest_path.write({
      "snapshot_id" => snapshot.fetch("snapshot_id"),
      "database" => ActiveRecord::Base.connection_db_config.database,
      "catalog" => { "reviewed_identities" => { source.fetch("key") => {
        "source" => { "ol_work_key" => source.fetch("key"), "title" => source.fetch("title"), "author" => source.fetch("author_name").first },
        "target" => book.attributes.slice("id", "ol_work_key", "title", "author"),
        "preserved_legacy_books" => preserved.map { |row| row.attributes.slice("id", "ol_work_key", "title", "author") }
      } } }
    }.to_json)
  end

  def write_snapshot
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: @docs }.to_json)
    snapshot = Rails.stub(:env, "development".inquiry) do
      OpenLibraryCatalogCapture.new(
        snapshot_path: @snapshot_path, lock_path: @directory.join("reading_scenario.lock"),
        contact_email: "contact@example.test"
      ).capture_catalog
    end
    # Snapshot preparation uses a stubbed capture. The operation under test must now stay offline.
    WebMock.reset!
    snapshot
  end

  def preflight_catalog
    Rails.stub(:env, "development".inquiry) { @preflight.preflight_catalog }
  end

  def create_selected_book(**overrides)
    Book.create!({
      ol_work_key: "/works/OL142000W", title: @docs.first.fetch("title"), author: "Gabriel García Márquez"
    }.merge(overrides))
  end

  def assert_read_only_failure
    before = Book.order(:id).map(&:attributes)
    editions_before = BookEdition.order(:id).map(&:attributes)
    error = assert_raises(OpenLibraryCatalogPreflight::PreflightError) { preflight_catalog }
    assert_equal before, Book.order(:id).map(&:attributes)
    assert_equal editions_before, BookEdition.order(:id).map(&:attributes)
    assert_not_requested :any, /https?:/
    error
  end
end
