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
    if @manifest["reading"].nil? && (@library_rows.any? || @session_rows.any?)
      raise DevelopmentReadingScenarioActivity::ActivityError, "Unrecorded reading data already exists for scenario accounts; review record IDs #{@library_rows.map(&:id) + @session_rows.map(&:id)} before importing."
    end
    intended = planned_reading
    unless @reading.is_a?(Hash) && @reading["expected_counts"] == intended.fetch("expected_counts") && @reading["records"].is_a?(Hash)
      raise DevelopmentReadingScenarioActivity::ActivityError, "Reading inventory differs from the recorded scenario plan."
    end
    intended.fetch("records").each do |group, records|
      actual = @reading.fetch("records")[group]
      unless actual.is_a?(Hash) && actual.keys.sort == records.keys.sort
        raise DevelopmentReadingScenarioActivity::ActivityError, "Recorded #{group} identities differ from the reading plan."
      end
      records.each do |identity, record|
        saved = actual.fetch(identity)
        unless saved.is_a?(Hash) && saved["expected_attributes"].is_a?(Hash) && saved.fetch("expected_attributes").slice(*record.fetch("expected_attributes").keys) == record.fetch("expected_attributes")
          raise DevelopmentReadingScenarioActivity::ActivityError, "Recorded #{group} #{identity} differs from its planned payload."
        end
        if group == "user_books" && saved["initial_status"] != record.fetch("initial_status")
          raise DevelopmentReadingScenarioActivity::ActivityError, "Recorded library status for #{identity} changed."
        end
      end
    end
    @library_matches = match_rows(@reading.fetch("records").fetch("user_books"), @library_rows, library: true)
    @session_matches = match_rows(@reading.fetch("records").fetch("reading_sessions"), @session_rows)
    tick_records = @manifest.fetch("ticks", {}).flat_map do |name, tick|
      tick.fetch("reading_sessions", {}).map { |identity, record| [ "#{name}/#{identity}", record ] }
    end.to_h
    @tick_matches = match_rows(tick_records, @session_rows)
    session_ids = (@session_matches.values + @tick_matches.values).compact.map(&:id)
    raise DevelopmentReadingScenarioActivity::ActivityError, "Two logical reading events claim the same session; review the manifest." unless session_ids.uniq.length == session_ids.length
    verify_no_unrecorded_rows(@library_rows, @library_matches.values, "library")
    verify_no_unrecorded_rows(@session_rows, @session_matches.values + @tick_matches.values, "session")
    @library_matches.each do |identity, row|
      verify_library_status(@reading.fetch("records").fetch("user_books").fetch(identity), row) if row
    end
  end

  def complete?
    @library_matches.values.all? && @session_matches.values.all?
  end

  def remember_library_entry(identity, row)
    @library_matches[identity] = row
  end

  def remember_session(identity, row, imported:)
    @session_matches[identity] = row
    @page_totals[[ row.user_id, row.book_id ]] = @page_totals.fetch([ row.user_id, row.book_id ], 0) + row.pages_read if imported
  end

  def verify_library_entry(record, row, identity)
    verify_reading_row(record, row, identity, library: true)
    verify_library_status(record, row)
  end

  def verify_reading_session(record, row, identity)
    verify_reading_row(record, row, identity)
  end

  def state_counts
    @library_matches.values.map(&:status).tally
  end

  def counts
    counts = {
      "user_books" => @library_matches.values.compact.length,
      "baseline_reading_sessions" => @session_matches.values.compact.length,
      "reading_sessions" => @session_matches.values.compact.length + @tick_matches.values.compact.length
    }
    unless counts.fetch("user_books") == 150 && counts.fetch("baseline_reading_sessions") == 300
      raise DevelopmentReadingScenarioActivity::ActivityError, "Unexpected reading inventory: #{counts.inspect}"
    end
    counts
  end

  def verify_final_library_states
    @library_matches.each do |identity, row|
      record = @reading.fetch("records").fetch("user_books").fetch(identity)
      expected = record.fetch("initial_status") == "reading" ? derived_status(row) : record.fetch("initial_status")
      raise DevelopmentReadingScenarioActivity::ActivityError, "Progress jobs did not reconcile library row ID #{row.id}: expected #{expected}, found #{row.status}." unless row.status == expected
    end
    unless (@library_matches.values.map(&:status).uniq & UserBook::STATUSES).length == 3
      raise DevelopmentReadingScenarioActivity::ActivityError, "Final library states do not include all three required states; review source page totals and activity."
    end
  end

  def snapshot_attributes(row, library: false)
    attributes = recorded_attributes(row)
    library ? attributes.except("status") : attributes
  end

  private

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

  def recorded_attributes(row)
    JSON.parse(row.attributes.except("id", "updated_at", "remember_created_at", "reset_password_token", "reset_password_sent_at").to_json)
  end
end
