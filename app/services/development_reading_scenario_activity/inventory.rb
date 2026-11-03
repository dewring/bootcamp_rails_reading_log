class DevelopmentReadingScenarioActivity::Inventory
  attr_reader :reading, :library_matches, :session_matches

  def initialize(plan:, manifest:, references:)
    @plan = plan
    @manifest = manifest
    @users = references.users
    @books = references.books
    @edition_ids = references.edition_ids
    @reading = @manifest["reading"] || planned_reading
  end

  def verify_reading
    load_reading_rows
    reject_unrecorded_start
    match_baseline_and_tick_rows
    verify_account_inventory
  end

  def remember_library_entry(identity, row)
    @library_matches[identity] = row
  end

  def remember_session(identity, row, imported:)
    @session_matches[identity] = row
    @page_totals[[ row.user_id, row.book_id ]] = @page_totals.fetch([ row.user_id, row.book_id ], 0) + row.pages_read if imported
  end

  def state_counts
    @library_matches.values.map(&:status).tally
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

  def reject_unrecorded_start
    return if @manifest["reading"] || (@library_rows.empty? && @session_rows.empty?)

    ids = @library_rows.map(&:id) + @session_rows.map(&:id)
    raise DevelopmentReadingScenarioActivity::ActivityError, "Unrecorded reading data already exists for scenario accounts; review record IDs #{ids} before importing."
  end

  def match_baseline_and_tick_rows
    @library_matches = match_rows(@reading.fetch("records").fetch("user_books"), @library_rows, library: true)
    @session_matches = match_rows(@reading.fetch("records").fetch("reading_sessions"), @session_rows)
    # Tick sessions belong to this scenario too; baseline replay must preserve them.
    tick_records = @manifest.fetch("ticks", {}).flat_map do |name, tick|
      tick.fetch("reading_sessions", {}).map { |identity, record| [ "#{name}/#{identity}", record ] }
    end.to_h
    @tick_matches = match_rows(tick_records, @session_rows)
  end

  def verify_account_inventory
    sessions = (@session_matches.values + @tick_matches.values).compact
    session_ids = sessions.map(&:id)
    raise DevelopmentReadingScenarioActivity::ActivityError, "Two logical reading events claim the same session; review the manifest." unless session_ids.uniq.length == session_ids.length

    verify_no_unrecorded_rows(@library_rows, @library_matches.values, "library")
    verify_no_unrecorded_rows(@session_rows, sessions, "session")
    @library_matches.each do |identity, row|
      verify_library_status(@reading.fetch("records").fetch("user_books").fetch(identity), row) if row
    end
  end

  def load_reading_rows
    @library_rows = UserBook.where(user_id: @users.values.map(&:id)).to_a
    @session_rows = ReadingSession.where(user_id: @users.values.map(&:id)).to_a
    @page_totals = @session_rows.group_by { |row| [ row.user_id, row.book_id ] }.transform_values { |rows| rows.sum(&:pages_read) }
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
    { "user_id" => @users.fetch(entry.fetch("reader")).id, "book_id" => @books.fetch(entry.fetch("work_key")).id }
  end

  def match_rows(records, rows, library: false)
    by_id = rows.index_by(&:id)
    records.to_h do |identity, record|
      expected = record.fetch("expected_attributes")
      if record["id"]
        row = by_id[record.fetch("id")]
        raise DevelopmentReadingScenarioActivity::ActivityError, "Recorded #{identity} (ID #{record.fetch('id')}) is missing; no automatic recreation is allowed." unless row

        verify_reading_row(record, row, identity, library: library)
      else
        matches = rows.select { |candidate| snapshot_attributes(candidate, library: library).slice(*expected.keys) == expected }
        if matches.length > 1
          raise DevelopmentReadingScenarioActivity::ActivityError, "Ambiguous reading payload #{identity}: record IDs #{matches.map(&:id)}; no records were changed."
        end
        row = matches.first
      end
      [ identity, row ]
    end
  end

  def verify_reading_row(record, row, identity, library: false)
    expected = record.fetch("expected_attributes")
    unless snapshot_attributes(row, library: library).slice(*expected.keys) == expected
      raise DevelopmentReadingScenarioActivity::ActivityError, "Recorded #{identity} (ID #{row.id}) changed; review before replaying."
    end
  end

  def verify_no_unrecorded_rows(rows, matches, label)
    extras = rows.map(&:id) - matches.compact.map(&:id)
    raise DevelopmentReadingScenarioActivity::ActivityError, "Unrecorded #{label} rows for scenario accounts: IDs #{extras}; review without deleting data." if extras.any?
  end

  def verify_library_status(record, row)
    initial = record.fetch("initial_status")
    allowed = initial == "reading" ? [ "reading", derived_status(row) ].uniq : [ initial ]
    raise DevelopmentReadingScenarioActivity::ActivityError, "Library row ID #{row.id} has an unexpected status #{row.status}; no automatic overwrite is allowed." unless allowed.include?(row.status)
  end

  def derived_status(row)
    pages = @books.values.find { |book| book.id == row.book_id }.total_pages
    total = @page_totals.fetch([ row.user_id, row.book_id ], 0)
    pages && total >= pages ? "finished" : "reading"
  end
end
