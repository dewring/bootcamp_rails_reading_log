require "test_helper"
require "tmpdir"

class OpenLibraryCatalogCaptureTest < ActiveSupport::TestCase
  setup do
    @directory = Pathname.new(Dir.mktmpdir("booknook-catalog-capture-"))
    @snapshot_path = @directory.join("snapshot/catalog.json")
    @lock_path = @directory.join("state/reading_scenario.lock")
    @monotonic = 0.0
    @waits = []
    @capture = build_capture
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "capture saves 100 source-ordered Works and preserves raw Work and representative edition metadata" do
    docs = documents(100)
    docs.first.merge!(
      "title" => "Преступление и наказание",
      "author_name" => [ "Фёдор Михайлович Достоевский" ],
      "isbn" => [ "unrelated-work-isbn" ],
      "publisher" => [ "Unrelated Work Publisher" ],
      "editions" => {
        "docs" => [ {
          "key" => "/books/OL37239326M", "title" => "Crime and Punishment",
          "isbn" => [ "9780140449136" ], "publisher" => [ "Penguin Classics" ]
        } ]
      }
    )
    body = JSON.pretty_generate({ "docs" => docs, "numFound" => 1_000 })
    request = stub_page(1, body: body)

    snapshot = capture_catalog
    saved = JSON.parse(@snapshot_path.read)

    assert_equal snapshot, saved
    assert_equal 100, saved.fetch("selected").length
    assert_equal docs.map { |doc| doc.fetch("key") }, saved.fetch("selected").map { |entry| entry.fetch("work_key") }
    assert_equal({ "work_key" => "/works/OL1W", "page" => 1, "index" => 0 }, saved.fetch("selected").first)
    page = saved.fetch("pages").first
    assert_equal body, page.fetch("raw_body")
    assert_equal "readinglog_count:[1 TO *]", page.fetch("parameters").fetch("q")
    assert_equal "readinglog", page.fetch("parameters").fetch("sort")
    assert_equal "100", page.fetch("parameters").fetch("limit")
    assert_equal "1", page.fetch("parameters").fetch("page")
    assert_equal OpenLibraryClient::CATALOG_FIELDS.join(","), page.fetch("parameters").fetch("fields")
    assert_equal 0, Time.iso8601(page.fetch("captured_at")).utc_offset
    assert_equal Digest::SHA256.hexdigest(JSON.generate(saved.fetch("pages"))), saved.fetch("snapshot_id")
    assert_equal docs.first, JSON.parse(page.fetch("raw_body")).fetch("docs").first
    assert_not_includes @snapshot_path.read, "contact@example.test"
    assert_equal 1, saved.fetch("http_attempts")
    assert_empty saved.fetch("skipped")
    assert_empty @waits
    assert_requested request, times: 1
  end

  test "capture normalizes Work keys and skips invalid and duplicate rows before choosing later results" do
    first_page = [
      documents(1).first.merge("key" => "OL1W"),
      documents(1).first,
      nil,
      { "key" => "/books/OL1M", "title" => "An edition", "author_name" => [ "Author" ] },
      documents(1).first.merge("key" => "/works/OL2W", "title" => " "),
      documents(1).first.merge("key" => "/works/OL3W", "author_name" => [])
    ]
    stub_page(1, docs: first_page)
    stub_page(2, docs: documents(100, start: 2))

    snapshot = capture_catalog

    assert_equal (1..100).map { |number| "/works/OL#{number}W" }, snapshot.fetch("selected").map { |entry| entry.fetch("work_key") }
    assert_equal [ "duplicate_work", "invalid_document", "invalid_work_key", "missing_title", "missing_author" ], snapshot.fetch("skipped").map { |entry| entry.fetch("reason") }
    assert_equal({ "work_key" => "/works/OL2W", "page" => 2, "index" => 0 }, snapshot.fetch("selected")[1])
    assert_equal [ 1.0 ], @waits
    assert_equal 2, snapshot.fetch("http_attempts")
  end

  test "capture retries a failed page at most twice and never exceeds nine HTTP attempts" do
    requests = (1..3).map do |page|
      stub_request(:get, "https://openlibrary.org/search.json")
        .with(query: hash_including(page: page.to_s))
        .to_return(
          { status: 429, body: "Slow down" },
          { status: 503, body: "Unavailable" },
          { status: 200, body: { docs: documents(35, start: (page - 1) * 35 + 1) }.to_json }
        )
    end

    snapshot = capture_catalog

    assert_equal 100, snapshot.fetch("selected").length
    assert_equal 3, snapshot.fetch("pages").length
    assert_equal 9, snapshot.fetch("http_attempts")
    assert_equal Array.new(8, 1.0), @waits
    requests.each { |request| assert_requested request, times: 3 }
  end

  test "timeout exhaustion preserves the previous snapshot and reports three failed attempts" do
    preserve_previous_snapshot
    request = stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: hash_including(page: "1"))
      .to_raise(Faraday::TimeoutError)

    error = assert_capture_failure

    assert_includes error.message, "Faraday::TimeoutError"
    assert_equal 3, error.report.fetch("http_attempts")
    assert_equal [ 1.0, 1.0 ], @waits
    assert_requested request, times: 3
  end

  test "429 exhaustion preserves the previous snapshot and honors bounded Retry-After seconds" do
    preserve_previous_snapshot
    request = stub_page(1, status: 429, body: "Slow down", headers: { "Retry-After" => "2" })

    error = assert_capture_failure

    assert_includes error.message, "HTTP 429"
    assert_equal 3, error.report.fetch("http_attempts")
    assert_equal [ 2.0, 2.0 ], @waits
    assert_requested request, times: 3
  end

  test "Retry-After HTTP dates delay the next attempt without changing the capture clock" do
    travel_to Time.utc(2026, 10, 30, 12) do
      stub_request(:get, "https://openlibrary.org/search.json")
        .with(query: hash_including(page: "1"))
        .to_return(
          { status: 429, headers: { "Retry-After" => 5.seconds.from_now.httpdate } },
          { status: 200, body: { docs: documents(100) }.to_json }
        )

      snapshot = capture_catalog

      assert_equal [ 5.0 ], @waits
      assert_equal Time.current.utc.iso8601(6), snapshot.fetch("captured_at")
    end
  end

  test "an excessive Retry-After stops capture instead of sleeping without a bound" do
    preserve_previous_snapshot
    request = stub_page(1, status: 429, body: "Slow down", headers: { "Retry-After" => "120" })

    error = assert_capture_failure

    assert_includes error.message, "retry capture later"
    assert_empty @waits
    assert_requested request, times: 1
  end

  test "invalid Retry-After retains the minimum one-second request spacing" do
    preserve_previous_snapshot
    stub_page(1, status: 503, body: "Unavailable", headers: { "Retry-After" => "invalid" })

    assert_capture_failure

    assert_equal [ 1.0, 1.0 ], @waits
  end

  test "a non-retryable rejection stops after one attempt and preserves the previous snapshot" do
    preserve_previous_snapshot
    request = stub_page(1, status: 422, body: '{"detail":"Invalid query"}')

    error = assert_capture_failure

    assert_includes error.message, "HTTP 422"
    assert_requested request, times: 1
  end

  test "invalid JSON stops immediately and preserves the previous snapshot" do
    preserve_previous_snapshot
    request = stub_page(1, body: "not JSON")

    error = assert_capture_failure

    assert_includes error.message, "Invalid JSON on page 1"
    assert_equal 1, error.report.fetch("http_attempts")
    assert_requested request, times: 1
  end

  test "a JSON error response without a docs array cannot become a successful catalog" do
    preserve_previous_snapshot
    request = stub_page(1, body: '{"detail":"Unavailable"}')

    error = assert_capture_failure

    assert_includes error.message, "expected a docs array"
    assert_requested request, times: 1
  end

  test "a shortage after three pages preserves the previous snapshot and reports invalid rows" do
    preserve_previous_snapshot
    requests = (1..3).map do |page|
      stub_page(page, docs: documents(20, start: (page - 1) * 20 + 1) + [ { "key" => "invalid" } ])
    end

    error = assert_capture_failure

    assert_includes error.message, "60/100"
    assert_equal 60, error.report.fetch("selected_count")
    assert_equal 3, error.report.fetch("skipped").length
    assert_equal [ 1.0, 1.0 ], @waits
    requests.each { |request| assert_requested request, times: 1 }
  end

  test "a failed first capture does not create a snapshot file" do
    stub_page(1, body: "not JSON")

    assert_raises(OpenLibraryCatalogCapture::CaptureError) { capture_catalog }

    assert_not @snapshot_path.exist?
  end

  test "capture replaces an old file only after collecting a complete valid snapshot" do
    preserve_previous_snapshot
    stub_page(1, docs: documents(100))

    snapshot = capture_catalog

    assert_equal snapshot, JSON.parse(@snapshot_path.read)
    assert_empty @snapshot_path.dirname.glob(".open_library_catalog*")
  end

  test "failed atomic replacement leaves the previous snapshot intact and cleans up its temporary file" do
    preserve_previous_snapshot
    stub_page(1, docs: documents(100))

    File.stub(:rename, ->(*) { raise IOError, "Interrupted file replacement" }) do
      assert_raises(IOError) { capture_catalog }
    end

    assert_equal @previous_bytes, @snapshot_path.binread
    assert_empty @snapshot_path.dirname.glob(".open_library_catalog*")
  end

  test "capture refuses other environments before creating directories or making requests" do
    [ "test", "production" ].each do |environment|
      Rails.stub(:env, environment.inquiry) do
        assert_raises(OpenLibraryCatalogCapture::CaptureError) { @capture.capture_catalog }
      end
    end

    assert_empty @directory.children
    assert_not_requested :get, /openlibrary\.org/
  end

  test "capture refuses a missing contact before creating directories or making requests" do
    capture = build_capture(contact_email: nil)

    Rails.stub(:env, "development".inquiry) do
      assert_raises(OpenLibraryCatalogCapture::CaptureError) { capture.capture_catalog }
    end

    assert_empty @directory.children
    assert_not_requested :get, /openlibrary\.org/
  end

  test "overlapping scenario operations are refused without an HTTP request or snapshot change" do
    preserve_previous_snapshot
    FileUtils.mkdir_p(@lock_path.dirname)

    File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      assert lock.flock(File::LOCK_EX | File::LOCK_NB)

      error = assert_capture_failure

      assert_includes error.message, "already running"
    end

    assert_not_requested :get, /openlibrary\.org/
  end

  test "capture releases its lock after failure so a later attempt can succeed" do
    request = stub_page(1, body: "not JSON")
    assert_raises(OpenLibraryCatalogCapture::CaptureError) { capture_catalog }
    remove_request_stub(request)
    stub_page(1, docs: documents(100))

    assert_equal 100, capture_catalog.fetch("selected").length
  end

  private

  def build_capture(contact_email: "contact@example.test")
    OpenLibraryCatalogCapture.new(
      snapshot_path: @snapshot_path,
      lock_path: @lock_path,
      contact_email: contact_email,
      clock: -> { @monotonic },
      sleeper: ->(seconds) {
        @waits.push(seconds)
        @monotonic += seconds
      }
    )
  end

  def capture_catalog
    Rails.stub(:env, "development".inquiry) { @capture.capture_catalog }
  end

  def documents(count, start: 1)
    Array.new(count) do |offset|
      number = start + offset
      { "key" => "/works/OL#{number}W", "title" => "Source book #{number}", "author_name" => [ "Source author #{number}" ] }
    end
  end

  def stub_page(page, docs: [], body: nil, status: 200, headers: {})
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: hash_including(page: page.to_s), headers: { "User-Agent" => "BookNook (contact@example.test)" })
      .to_return(status: status, body: body || { docs: docs }.to_json, headers: headers)
  end

  def preserve_previous_snapshot
    FileUtils.mkdir_p(@snapshot_path.dirname)
    @previous_bytes = '{"previous":"valid snapshot must remain byte-for-byte unchanged"}'
    @snapshot_path.write(@previous_bytes)
  end

  def assert_capture_failure
    error = assert_raises(OpenLibraryCatalogCapture::CaptureError) { capture_catalog }
    assert_equal @previous_bytes, @snapshot_path.binread
    error
  end
end
