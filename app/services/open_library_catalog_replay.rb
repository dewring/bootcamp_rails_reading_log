class OpenLibraryCatalogReplay
  class ReplayError < StandardError; end

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    as_of: DevelopmentReadingScenarioPlan.default_reference_time, manifest: nil)
    @snapshot_path = Pathname.new(snapshot_path)
    @scenario_manifest = manifest || DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
  end

  def replay_catalog
    with_catalog_context do
      @scenario_manifest.save_scenario
      @plan.fetch("books").each { |entry| import_catalog_entry(entry) }
      record_catalog_counts
      record_skipped_book_conflicts
      record_skipped_edition_conflicts
      @manifest.fetch("catalog")["status"] = "complete"
      @scenario_manifest.save_scenario
      prepare_cover_previews
      @manifest.deep_dup
    end
  end

  def preflight_catalog
    with_catalog_context { @manifest.fetch("catalog").deep_dup }
  end

  private

  def prepare_cover_previews
    books = Book.where(id: @books.values.map(&:id)).with_attached_cover_image.index_by(&:ol_work_key)
    DevelopmentReadingScenarioCoverPreviews.new(
      snapshot: JSON.parse(@snapshot_path.read), books: books,
      manifest: @manifest, scenario_manifest: @scenario_manifest
    ).prepare_previews
  end

  def with_catalog_context
    @scenario_manifest.with_exclusive_access do
      @plan = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path, manifest_path: @scenario_manifest.path).preflight_catalog(skip_book_conflicts: true)
      load_catalog_records
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: @plan.fetch("snapshot_id"))
      @manifest["catalog"] ||= planned_catalog
      verify_recorded_rows
      yield
    end
  end

  def load_catalog_records
    book_keys = @plan.fetch("books").filter_map { |entry| entry.dig("book_attributes", "ol_work_key") unless entry["book_skip"] }
    edition_keys = @plan.fetch("books").filter_map { |entry| entry["edition_attributes"]&.fetch("ol_edition_key") }
    @books = Book.where(ol_work_key: book_keys).index_by(&:ol_work_key)
    @editions = BookEdition.where(ol_edition_key: edition_keys).index_by(&:ol_edition_key)
  end

  def planned_catalog
    records = @plan.fetch("books").to_h do |entry|
      attributes = entry.fetch("book_attributes")
      key = attributes.fetch("ol_work_key")
      edition_attributes = entry["edition_attributes"]
      book = @books[key]
      edition = edition_attributes && @editions[edition_attributes.fetch("ol_edition_key")]
      edition_record = if edition_attributes
        planned_record(edition, edition_attributes)
      else
        { "result" => "skipped", "reason" => "No representative Edition returned" }.merge(entry.fetch("edition_skip", {}))
      end
      [ key, {
        "book" => planned_record(book, attributes),
        "edition" => edition_record,
        "source_page_estimate" => entry["page_estimate_source"] ? { "field" => entry.fetch("page_estimate_source"), "value" => attributes.fetch("total_pages") } : nil,
        "missing_optional_fields" => entry.fetch("missing_optional_fields")
      } ]
    end
    {
      "status" => "pending",
      "expected_counts" => expected_counts,
      "records" => records
    }
  end

  def planned_record(record, attributes)
    {
      "id" => record&.id,
      "origin" => record ? "reused" : "imported",
      "result" => record ? "reused" : nil,
      "expected_attributes" => record ? recorded_attributes(record) : attributes
    }
  end

  def verify_recorded_rows
    @plan.fetch("books").each do |entry|
      next if entry["book_skip"]

      key = entry.fetch("book_attributes").fetch("ol_work_key")
      pair = @manifest.fetch("catalog").fetch("records").fetch(key)
      book = @books[key]
      verify_recorded_row(pair.fetch("book"), book, key)
      next unless entry["edition_attributes"]

      edition_key = entry.fetch("edition_attributes").fetch("ol_edition_key")
      edition = @editions[edition_key]
      verify_recorded_row(pair.fetch("edition"), edition, edition_key)
      if edition && edition.book_id != book&.id
        raise ReplayError, "Recorded Edition #{edition_key} belongs to an unexpected Book (ID #{edition.id})."
      end
    end
  end

  def verify_recorded_row(record, row, key)
    if record["id"]
      row_key = row.is_a?(Book) ? row.ol_work_key : row&.ol_edition_key
      unless row && row.id == record.fetch("id") && row_key == key
        raise ReplayError, "Recorded #{key} (ID #{record.fetch('id')}) is missing or its identity changed; no automatic recreation is allowed."
      end

      # The verified catalog identity is unchanged. Keep the database's current metadata.
      return
    end
    return unless row

    expected = record.fetch("expected_attributes")
    unless recorded_attributes(row).slice(*expected.keys) == expected
      raise ReplayError, "Recorded #{key} (ID #{row.id}) changed; review it before replaying."
    end
  end

  def import_catalog_entry(entry)
    book_attributes = entry.fetch("book_attributes")
    key = book_attributes.fetch("ol_work_key")
    edition_attributes = entry["edition_attributes"]
    pair = @manifest.fetch("catalog").fetch("records").fetch(key)
    if entry["book_skip"]
      pair.fetch("book").merge!("result" => "skipped", "reason" => "book_unavailable", "conflicts" => entry.fetch("book_skip"))
      pair["edition"] = entry.fetch("edition_skip").merge("result" => "skipped") if entry["edition_skip"]
      @scenario_manifest.save_scenario
      return
    end
    book = @books[key]
    edition = edition_attributes && @editions[edition_attributes.fetch("ol_edition_key")]
    book_result = book ? "reused" : "imported"
    edition_result = edition ? "reused" : "imported"

    Book.transaction(requires_new: true) do
      book.lock! if book
      edition.lock! if edition
      verify_recorded_row(pair.fetch("book"), book, key)
      verify_recorded_row(pair.fetch("edition"), edition, edition_attributes.fetch("ol_edition_key")) if edition_attributes
      if edition && edition.book_id != book&.id
        raise ReplayError, "Edition #{edition.ol_edition_key} (ID #{edition.id}) changed its Book during replay."
      end
      book ||= Book.create!(book_attributes)
      if edition_attributes
        edition ||= BookEdition.create!(edition_attributes.merge("book" => book))
      end
    end

    @books[key] = book
    @editions[edition.ol_edition_key] = edition if edition
    record_saved_row(pair.fetch("book"), book, book_result)
    record_saved_row(pair.fetch("edition"), edition, edition_result) if edition
    pair["edition"] = entry.fetch("edition_skip").merge("result" => "skipped") if entry["edition_skip"]
    @scenario_manifest.save_scenario
  rescue ActiveRecord::RecordInvalid => error
    kind = error.record.is_a?(BookEdition) ? "edition" : "book"
    pair.fetch(kind)["result"] = "failed"
    pair.fetch(kind)["errors"] = error.record.errors.full_messages
    @scenario_manifest.save_scenario
    raise
  end

  def record_saved_row(record, row, result)
    record["id"] = row.id
    record["result"] = result
    record["expected_attributes"] = recorded_attributes(row)
    record.delete("errors")
  end

  def recorded_attributes(record)
    # Edition saves normally touch the parent Book; updated_at is not catalog content.
    JSON.parse(record.attributes.except("id", "updated_at").to_json)
  end

  def record_catalog_counts
    @manifest.fetch("catalog")["actual_counts"] = { "books" => @books.length, "book_editions" => @editions.length }
  end

  def expected_counts
    {
      "books" => OpenLibraryCatalogCapture::TARGET_COUNT,
      "book_editions" => @plan.fetch("books").count { |entry| entry["edition_attributes"] }
    }
  end

  def record_skipped_edition_conflicts
    catalog = @manifest.fetch("catalog")
    catalog["skipped_edition_conflicts"] = catalog.fetch("records").filter_map do |work_key, pair|
      edition = pair.fetch("edition")
      next unless edition["result"] == "skipped" && edition["edition_key"]

      edition.except("result").merge("work_key" => work_key)
    end
  end

  def record_skipped_book_conflicts
    catalog = @manifest.fetch("catalog")
    catalog["skipped_book_conflicts"] = catalog.fetch("records").filter_map do |work_key, pair|
      book = pair.fetch("book")
      next unless book["result"] == "skipped"

      { "work_key" => work_key, "record_id" => book["id"], "conflicts" => book.fetch("conflicts") }
    end
  end
end
