require "digest"
require "fileutils"
require "set"
require "tempfile"
require "time"

class OpenLibraryCatalogCapture
  class CaptureError < StandardError
    attr_reader :report

    def initialize(message, report:)
      @report = report
      super(message)
    end
  end

  TARGET_COUNT = 100
  MAX_PAGES = 3
  ATTEMPTS_PER_PAGE = 3
  MAX_RETRY_DELAY = 60

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    contact_email: ENV["OPEN_LIBRARY_CONTACT_EMAIL"], client: OpenLibraryClient.new,
    clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
    @snapshot_path = Pathname.new(snapshot_path)
    @lock_path = Pathname.new(lock_path)
    @contact_email = contact_email
    @client = client
    @clock = clock
    @sleeper = sleeper
  end

  def capture_catalog
    prepare_capture
    validate_capture_settings
    FileUtils.mkdir_p(@lock_path.dirname)

    File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      fail_capture("Another reading scenario operation is already running") unless lock.flock(File::LOCK_EX | File::LOCK_NB)

      snapshot = collect_snapshot
      save_snapshot(snapshot)
      snapshot
    end
  end

  private

  def prepare_capture
    @attempts = 0
    @pages = []
    @selected = []
    @skipped = []
    @work_keys = Set.new
    @next_attempt_at = @clock.call
  end

  def validate_capture_settings
    fail_capture("Catalog capture is only available in development") unless Rails.env.development?
    return if @contact_email.is_a?(String) && URI::MailTo::EMAIL_REGEXP.match?(@contact_email)

    fail_capture("Set OPEN_LIBRARY_CONTACT_EMAIL to a reachable contact address before capture")
  end

  def collect_snapshot
    1.upto(MAX_PAGES) do |page|
      response = fetch_page(page)
      body = utf8_response_body(response.body, page)
      docs = parse_documents(body, page)
      @pages.push({
        "page" => page,
        "parameters" => URI.decode_www_form(response.env.url.query).to_h,
        "captured_at" => Time.current.utc.iso8601(6),
        "raw_body" => body
      })
      select_works(docs, page)
      break if @selected.length == TARGET_COUNT
    end

    unless @selected.length == TARGET_COUNT
      fail_capture("Incomplete catalog: #{@selected.length}/#{TARGET_COUNT} valid distinct Works after #{@pages.length} pages")
    end

    {
      "version" => 1,
      "source" => "#{OpenLibraryClient::BASE_URL}/search.json",
      "snapshot_id" => Digest::SHA256.hexdigest(JSON.generate(@pages)),
      "captured_at" => @pages.first.fetch("captured_at"),
      "selection_rule" => "First 100 valid distinct Works in readinglog search response order",
      "http_attempts" => @attempts,
      "pages" => @pages,
      "selected" => @selected,
      "skipped" => @skipped
    }
  end

  def fetch_page(page)
    last_failure = nil

    ATTEMPTS_PER_PAGE.times do |attempt|
      wait_for_request_slot
      @attempts += 1

      begin
        response = @client.fetch_catalog_page(page: page, contact_email: @contact_email)
      rescue Faraday::Error => error
        last_failure = error.class.name
        next
      end

      return response if response.status == 200

      last_failure = "HTTP #{response.status}"
      break unless [ 408, 429 ].include?(response.status) || (500..599).cover?(response.status)

      defer_retry(response) if attempt < ATTEMPTS_PER_PAGE - 1
    end

    fail_capture("Capture stopped at page #{page}: #{last_failure}; request budget exhausted or response is not retryable")
  end

  def wait_for_request_slot
    remaining = @next_attempt_at - @clock.call
    @sleeper.call(remaining) if remaining.positive?
    @next_attempt_at = @clock.call + 1
  end

  def defer_retry(response)
    header = response.headers["retry-after"].to_s
    return if header.empty?

    delay = if header.match?(/\A\d+\z/)
      header.to_i
    else
      Time.httpdate(header) - Time.current
    end
    fail_capture("Server requested a retry wait longer than #{MAX_RETRY_DELAY} seconds; retry capture later") if delay > MAX_RETRY_DELAY
    @next_attempt_at = [ @next_attempt_at, @clock.call + delay ].max
  rescue ArgumentError
    # An invalid Retry-After value still retains the minimum one-second request spacing.
    nil
  end

  def utf8_response_body(body, page)
    fail_capture("Invalid search response on page #{page}: expected JSON text") unless body.is_a?(String)

    text = body.dup.force_encoding(Encoding::UTF_8)
    fail_capture("Invalid UTF-8 JSON on page #{page}") unless text.valid_encoding?

    text
  end

  def parse_documents(body, page)
    parsed = JSON.parse(body)
    unless parsed.is_a?(Hash) && parsed["docs"].is_a?(Array)
      fail_capture("Invalid search response on page #{page}: expected a docs array")
    end
    parsed.fetch("docs")
  rescue JSON::ParserError
    fail_capture("Invalid JSON on page #{page}")
  end

  def select_works(docs, page)
    docs.each_with_index do |doc, index|
      break if @selected.length == TARGET_COUNT

      work_key = normalized_work_key(doc)
      reason = invalid_document_reason(doc, work_key)
      reason ||= "duplicate_work" if @work_keys.include?(work_key)
      if reason
        @skipped.push({ "page" => page, "index" => index, "reason" => reason })
        next
      end

      @work_keys.add(work_key)
      @selected.push({ "work_key" => work_key, "page" => page, "index" => index })
    end
  end

  def normalized_work_key(doc)
    return unless doc.is_a?(Hash) && doc["key"].is_a?(String)

    match = doc["key"].strip.match(%r{\A(?:/works/)?(OL\d+W)\z})
    "/works/#{match[1]}" if match
  end

  def invalid_document_reason(doc, work_key)
    return "invalid_document" unless doc.is_a?(Hash)
    return "invalid_work_key" unless work_key
    return "missing_title" unless doc["title"].is_a?(String) && doc["title"].present?
    return "missing_author" unless doc["author_name"].is_a?(Array) && doc["author_name"].any? { |name| name.is_a?(String) && name.present? }

    nil
  end

  def save_snapshot(snapshot)
    FileUtils.mkdir_p(@snapshot_path.dirname)
    # Rename within the same directory so readers see either the old complete file or the new one.
    Tempfile.create([ ".open_library_catalog", ".json" ], @snapshot_path.dirname) do |file|
      file.write(JSON.pretty_generate(snapshot))
      file.write("\n")
      file.flush
      file.fsync
      File.rename(file.path, @snapshot_path)
    end
  end

  def fail_capture(message)
    raise CaptureError.new("#{message}. Previous snapshot was not replaced.", report: {
      "http_attempts" => @attempts,
      "selected_count" => @selected.length,
      "skipped" => @skipped
    })
  end
end
