require "digest"
require "set"
require "time"

class OpenLibraryCatalogPreflight
  class PreflightError < StandardError
    attr_reader :report

    def initialize(message, report: {})
      @report = report
      super(message)
    end
  end

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH)
    @snapshot_path = Pathname.new(snapshot_path)
    @manifest_path = Pathname.new(manifest_path)
  end

  def preflight_catalog
    raise PreflightError, "Catalog preflight is only available in development" unless Rails.env.development?

    @snapshot = JSON.parse(@snapshot_path.read)
    @conflicts = []
    validate_provenance
    load_reviewed_identities
    @entries = selected_documents.map { |key, doc| catalog_entry(key, doc) }
    inspect_existing_records
    report = { "snapshot_id" => @snapshot.fetch("snapshot_id"), "books" => @entries, "conflicts" => @conflicts }
    if @conflicts.any?
      raise PreflightError.new("Catalog conflicts require explicit review; no records were changed.", report: report)
    end
    report
  rescue Errno::ENOENT
    raise PreflightError, "Snapshot is missing. Run development_scenario:capture_catalog before offline replay."
  rescue JSON::ParserError
    raise PreflightError, "Snapshot or saved API response contains invalid JSON; capture a valid snapshot before replay."
  end

  private

  def load_reviewed_identities
    @reviewed_identities = {}
    return unless @manifest_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    return unless manifest["snapshot_id"] == @snapshot.fetch("snapshot_id") &&
      manifest["database"] == ActiveRecord::Base.connection_db_config.database

    @reviewed_identities = manifest.dig("catalog", "reviewed_identities") || {}
  rescue JSON::ParserError
    raise DevelopmentReadingScenarioManifest::ManifestError, "The reading scenario manifest contains invalid JSON; preserve it and inspect the failure before replaying."
  end

  def reviewed_identity(attributes)
    review = @reviewed_identities[attributes.fetch("ol_work_key")]
    return unless review && review.fetch("source") == attributes.slice("ol_work_key", "title", "author")

    review
  end

  def reviewed_book?(book, attributes)
    expected = reviewed_identity(attributes)&.fetch("target")
    expected && expected.keys.sort == [ "author", "id", "ol_work_key", "title" ] &&
      book.attributes.slice(*expected.keys) == expected
  end

  def reviewed_preserved_book?(book, attributes)
    preserved = reviewed_identity(attributes)&.fetch("preserved_legacy_books", []) || []
    preserved.any? do |expected|
      expected.keys.sort == [ "author", "id", "ol_work_key", "title" ] &&
        book.attributes.slice(*expected.keys) == expected
    end
  end

  def validate_provenance
    invalid_snapshot("unsupported snapshot") unless @snapshot.is_a?(Hash) && @snapshot["version"] == 1
    invalid_snapshot("unexpected API source") unless @snapshot["source"] == "#{OpenLibraryClient::BASE_URL}/search.json"
    @pages = @snapshot["pages"]
    unless @pages.is_a?(Array) && (1..OpenLibraryCatalogCapture::MAX_PAGES).cover?(@pages.length)
      invalid_snapshot("expected one to three source pages")
    end
    unless @snapshot["snapshot_id"] == Digest::SHA256.hexdigest(JSON.generate(@pages))
      invalid_snapshot("source page checksum does not match")
    end
    @pages.each_with_index { |page, index| validate_source_page(page, index + 1) }
  end

  def validate_source_page(page, number)
    expected = {
      "q" => OpenLibraryClient::CATALOG_QUERY, "sort" => "readinglog", "page" => number.to_s,
      "limit" => "100", "fields" => OpenLibraryClient::CATALOG_FIELDS.join(",")
    }
    unless page.is_a?(Hash) && page["page"] == number && page["parameters"] == expected && page["raw_body"].is_a?(String)
      invalid_snapshot("source page #{number} does not match the recorded readinglog request")
    end
    unless page["captured_at"].is_a?(String) && Time.iso8601(page["captured_at"]).utc_offset.zero?
      invalid_snapshot("source page #{number} must have a UTC capture time")
    end
  rescue ArgumentError
    invalid_snapshot("source page #{number} has an invalid capture time")
  end

  def selected_documents
    selections = []
    documents = []
    seen = Set.new
    @pages.each do |page|
      parsed = JSON.parse(page.fetch("raw_body"))
      invalid_snapshot("source response must contain a docs array") unless parsed.is_a?(Hash) && parsed["docs"].is_a?(Array)
      parsed.fetch("docs").each_with_index do |doc, index|
        break if selections.length == OpenLibraryCatalogCapture::TARGET_COUNT

        key = doc.is_a?(Hash) ? normalized_work_key(doc["key"]) : nil
        next unless valid_work?(doc, key) && seen.add?(key)

        selections.push({ "work_key" => key, "page" => page.fetch("page"), "index" => index })
        documents.push([ key, doc ])
      end
    end
    unless selections.length == OpenLibraryCatalogCapture::TARGET_COUNT && selections == @snapshot["selected"]
      invalid_snapshot("selection must be the first 100 valid distinct Works in source order")
    end
    documents
  end

  def valid_work?(doc, key)
    key && doc["title"].is_a?(String) && doc["title"].present? &&
      doc["author_name"].is_a?(Array) && doc["author_name"].any? { |name| name.is_a?(String) && name.present? }
  end

  def catalog_entry(key, doc)
    pages = doc["number_of_pages_median"]
    pages = nil unless pages.is_a?(Integer) && pages.positive?
    description = doc["description"] || doc["work.description"]
    description = description["value"] if description.is_a?(Hash)
    attributes = {
      "ol_work_key" => key,
      "title" => doc.fetch("title").strip,
      "author" => doc.fetch("author_name").find { |name| name.is_a?(String) && name.present? }.strip,
      "description" => description.is_a?(String) ? description : nil,
      "subjects" => doc["subject"].is_a?(Array) ? doc["subject"].select { |subject| subject.is_a?(String) } : nil,
      "total_pages" => pages
    }
    edition = representative_edition(key, doc)
    {
      "book_attributes" => attributes,
      "edition_attributes" => edition,
      "page_estimate_source" => pages ? "number_of_pages_median" : nil,
      "missing_optional_fields" => attributes.select { |_, value| value.nil? }.keys,
      "book_status" => "pending",
      "edition_status" => edition ? "pending" : "skipped"
    }
  end

  def representative_edition(work_key, doc)
    editions = doc["editions"]
    return nil unless editions.is_a?(Hash) && editions["docs"].is_a?(Array) && editions["docs"].any?

    edition = editions.fetch("docs").first
    invalid_snapshot("invalid representative Edition for #{work_key}") unless edition.is_a?(Hash)
    key = normalized_edition_key(edition["key"])
    invalid_snapshot("representative Edition for #{work_key} needs its own valid key") unless key
    if edition.key?("work_key") && !Array(edition["work_key"]).any? { |value| normalized_work_key(value) == work_key }
      add_conflict("edition_work_mismatch", work_key: work_key, edition_key: key)
    end
    date = first_text(edition["publish_date"])
    year = Array(edition["publish_year"]).find { |value| value.is_a?(Integer) && value.positive? }
    {
      "ol_edition_key" => key,
      "title" => first_text(edition["title"]),
      "isbn" => first_text(edition["isbn"]),
      "publisher" => first_text(edition["publisher"]),
      "publish_year" => date || year&.to_s,
      "language" => first_text(edition["language"]),
      "format" => first_text(edition["format"]),
      "page_count" => nil
    }
  end

  def inspect_existing_records
    keys = @entries.map { |entry| entry.fetch("book_attributes").fetch("ol_work_key") }
    @selected_work_keys = keys.to_set
    titles = @entries.flat_map { |entry| comparable_text(entry.fetch("book_attributes").fetch("title")) }.uniq
    @existing_books = Book.where("BTRIM(ol_work_key) IN (?)", external_key_variants(keys))
      .or(Book.where("LOWER(BTRIM(title)) IN (?)", titles)).order(:id).to_a
    edition_keys = @entries.filter_map { |entry| entry["edition_attributes"]&.fetch("ol_edition_key") }
    @existing_editions = BookEdition.where("BTRIM(ol_edition_key) IN (?)", external_key_variants(edition_keys)).order(:id).to_a
    inspect_shared_edition_keys
    @entries.each do |entry|
      inspect_existing_book(entry)
      inspect_existing_edition(entry) if entry["edition_attributes"]
    end
  end

  def inspect_shared_edition_keys
    @entries.select { |entry| entry["edition_attributes"] }.group_by { |entry| entry.fetch("edition_attributes").fetch("ol_edition_key") }.each do |key, entries|
      next if entries.one?

      add_conflict("edition_selected_for_multiple_works", edition_key: key,
        work_keys: entries.map { |entry| entry.fetch("book_attributes").fetch("ol_work_key") })
    end
  end

  def inspect_existing_book(entry)
    attributes = entry.fetch("book_attributes")
    key = attributes.fetch("ol_work_key")
    keyed = @existing_books.select { |book| normalized_work_key(book.ol_work_key) == key }
    matching = @existing_books.select { |book| same_title_and_author?(book, attributes) }
    unkeyed = matching.select { |book| book.ol_work_key.blank? && !reviewed_preserved_book?(book, attributes) }
    other_keyed = matching.reject { |book| book.ol_work_key.blank? || @selected_work_keys.include?(normalized_work_key(book.ol_work_key)) }
    add_conflict("legacy_unkeyed_book", work_key: key, record_ids: unkeyed.map(&:id)) if unkeyed.any?
    add_conflict("different_work_key", work_key: key, record_ids: other_keyed.map(&:id)) if other_keyed.any?
    if keyed.length > 1
      add_conflict("ambiguous_work_identity", work_key: key, record_ids: keyed.map(&:id))
      return
    end
    return if keyed.empty?

    book = keyed.first
    unless book.ol_work_key == key && same_title_and_author?(book, attributes)
      add_conflict("conflicting_work_identity", work_key: key, record_ids: [ book.id ])
      return
    end
    entry["existing_book_id"] = book.id
    entry["book_status"] = "reused"
  end

  def inspect_existing_edition(entry)
    key = entry.fetch("edition_attributes").fetch("ol_edition_key")
    existing = @existing_editions.select { |edition| normalized_edition_key(edition.ol_edition_key) == key }
    return if existing.empty?

    unless existing.one? && existing.first.ol_edition_key == key && existing.first.book_id == entry["existing_book_id"]
      add_conflict("conflicting_edition_identity", edition_key: key, record_ids: existing.map(&:id), book_ids: existing.map(&:book_id))
      return
    end
    entry["existing_edition_id"] = existing.first.id
    entry["edition_status"] = "reused"
  end

  def same_title_and_author?(book, attributes)
    return true if reviewed_book?(book, attributes)

    comparable_text(attributes.fetch("title")).include?(book.title.strip.downcase) &&
      comparable_text(attributes.fetch("author")).include?(book.author.strip.downcase)
  end

  def comparable_text(value)
    # Legacy seeds passed through titleize, which also replaces underscores and some punctuation.
    [ value.strip.downcase, value.titleize.strip.downcase ].uniq
  end

  def external_key_variants(keys)
    keys.flat_map { |key| [ key, key.split("/").last ] }
  end

  def normalized_work_key(value)
    return unless value.is_a?(String)

    match = value.strip.match(%r{\A(?:/works/)?(OL\d+W)\z})
    "/works/#{match[1]}" if match
  end

  def normalized_edition_key(value)
    return unless value.is_a?(String)

    match = value.strip.match(%r{\A(?:/books/)?(OL\d+M)\z})
    "/books/#{match[1]}" if match
  end

  def first_text(value)
    Array(value).find { |item| item.is_a?(String) && item.present? }
  end

  def add_conflict(reason, **details)
    @conflicts.push(details.stringify_keys.merge(
      "reason" => reason,
      "next_step" => "Review these identities explicitly; resolve the mapping or use a corrected snapshot before importing. No automatic merge or overwrite is allowed."
    ))
  end

  def invalid_snapshot(reason)
    raise PreflightError, "Invalid catalog snapshot: #{reason}. No records were changed."
  end
end
