class DevelopmentReadingScenarioActivity::Inventory
  attr_reader :reading, :library_matches, :session_matches

  def initialize(plan:, manifest:, references:)
    @plan = plan
    @manifest = manifest
    @users = references.users
    @available_user_ids = @users.values.compact.map(&:id).to_set
    @books = references.books
    @available_book_ids = @books.values.compact.map(&:id).to_set
    @edition_ids = references.edition_ids
    @first_import = !@manifest.key?("reading")
    @reading = @manifest["reading"] || planned_reading
  end

  def verify_reading
    load_reading_rows
    match_baseline_and_tick_rows
    report_unplanned_reading_rows
  end

  def remember_library_entry(identity, row)
    @library_matches[identity] = row
  end

  def remember_session(identity, row)
    @session_matches[identity] = row
  end

  def state_counts
    @library_matches.values.compact.map(&:status).tally
  end

  def counts
    {
      "user_books" => @library_matches.values.compact.length,
      "baseline_reading_sessions" => @session_matches.values.compact.length,
      "reading_sessions" => @session_matches.values.compact.length + @tick_matches.values.compact.length
    }
  end

  def snapshot_attributes(row, library: false)
    attributes = row.attributes.except("id", "updated_at").as_json
    library ? attributes.except("status") : attributes
  end

  private

  def match_baseline_and_tick_rows
    @library_matches = match_rows(@reading.fetch("records").fetch("user_books"), @library_rows, library: true)
    adjust_pending_shelves_for_existing_reading
    @session_matches = match_rows(@reading.fetch("records").fetch("reading_sessions"), @session_rows)
    # Tick sessions belong to this scenario too; baseline replay must preserve them.
    tick_records = @manifest.fetch("ticks", {}).flat_map do |name, tick|
      tick.fetch("reading_sessions", {}).map { |identity, record| [ "#{name}/#{identity}", record ] }
    end.to_h
    @tick_matches = match_rows(tick_records, @session_rows)
  end

  def adjust_pending_shelves_for_existing_reading
    active_pairs = @session_rows.map { |row| [ row.user_id, row.book_id ] }.to_set
    @reading.fetch("records").fetch("user_books").each do |identity, record|
      next if @library_matches[identity] || record["result"] == "skipped" || record["initial_status"] != "want_to_read"

      pair = record.fetch("expected_attributes").values_at("user_id", "book_id")
      record["initial_status"] = "reading" if active_pairs.include?(pair)
    end
  end

  def report_unplanned_reading_rows
    sessions = (@session_matches.values + @tick_matches.values).compact
    @reading["unplanned_record_ids"] = {
      "user_books" => (@library_rows.map(&:id) - @library_matches.values.compact.map(&:id)).sort,
      "reading_sessions" => (@session_rows.map(&:id) - sessions.map(&:id)).sort
    }
  end

  def load_reading_rows
    @library_rows = UserBook.where(user_id: @available_user_ids.to_a).to_a
    @session_rows = ReadingSession.where(user_id: @available_user_ids.to_a).to_a
  end

  def planned_reading
    library = @plan.fetch("user_books").to_h do |entry|
      [ entry.fetch("identity"), {
        "id" => nil, "result" => nil, "initial_status" => entry.fetch("attributes").fetch("status"),
        "completion_note" => entry.fetch("completion_note"),
        "expected_attributes" => resolved_pair(entry)
      } ]
    end
    sessions = @plan.fetch("reading_sessions").to_h do |entry|
      [ entry.fetch("identity"), {
        "id" => nil, "result" => nil,
        "expected_attributes" => resolved_pair(entry).merge(entry.fetch("attributes")).merge("book_edition_id" => @edition_ids.fetch(entry.fetch("work_key")))
      } ]
    end
    { "status" => "pending", "expected_counts" => { "user_books" => 150, "reading_sessions" => 300 },
      "records" => { "user_books" => library, "reading_sessions" => sessions } }
  end

  def resolved_pair(entry)
    { "user_id" => @users.fetch(entry.fetch("reader"))&.id, "book_id" => @books.fetch(entry.fetch("work_key"))&.id }
  end

  def match_rows(records, rows, library: false)
    rows_by_id = rows.index_by(&:id)
    records.to_h do |identity, record|
      row = match_reading_record(record, rows_by_id, rows, library: library)
      record["origin"] = "existing" if @first_import && library && row
      [ identity, row ]
    end
  end

  def match_reading_record(record, rows_by_id, rows, library:)
    reason = unavailable_reading_dependency(record.fetch("expected_attributes"))
    if reason
      record.merge!("result" => "skipped", "reason" => reason)
      return
    end
    return if record["result"] == "skipped"

    if record["id"]
      find_saved_reading_record(record, rows_by_id)
    else
      find_interrupted_reading_record(record, rows, library: library)
    end
  end

  def unavailable_reading_dependency(attributes)
    return "account_unavailable" unless @available_user_ids.include?(attributes["user_id"])
    return "book_unavailable" unless @available_book_ids.include?(attributes["book_id"])

    nil
  end

  def find_saved_reading_record(record, rows_by_id)
    row = rows_by_id[record.fetch("id")]
    return row if row && same_pair?(row, record.fetch("expected_attributes"))

    record.merge!("result" => "skipped", "reason" => row ? "reading_identity_changed" : "recorded_reading_row_missing")
    nil
  end

  def find_interrupted_reading_record(record, rows, library:)
    expected = record.fetch("expected_attributes")
    matches = if library
      rows.select { |candidate| same_pair?(candidate, expected) }
    else
      rows.select { |candidate| snapshot_attributes(candidate).slice(*expected.keys) == expected }
    end
    if matches.length > 1
      record.merge!("result" => "skipped", "reason" => "ambiguous_reading_payload", "record_ids" => matches.map(&:id).sort)
      return
    end
    matches.first
  end

  def same_pair?(row, attributes)
    [ row.user_id, row.book_id ] == attributes.values_at("user_id", "book_id")
  end
end
