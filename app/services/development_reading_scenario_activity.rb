class DevelopmentReadingScenarioActivity
  class ActivityError < StandardError; end

  CALLBACK_JOBS = [ "BookProgressJob", "BadgeAwardJob", "ChallengeProgressJob", "BookClubLeaderboardJob" ].freeze

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: Rails.root.join("storage/development_scenarios/week15.json"),
    lock_path: Rails.root.join("storage/development_scenarios/week15.lock"),
    as_of: Time.zone.local(2026, 10, 30, 12), manifest: nil)
    @snapshot_path = snapshot_path
    @as_of = as_of
    @scenario_manifest = manifest || DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
  end

  def replay_reading
    with_reading_context do
      if @manifest["reading"].nil? && (@library_rows.any? || @session_rows.any?)
        raise ActivityError, "Unrecorded reading data already exists for scenario accounts; review record IDs #{@library_rows.map(&:id) + @session_rows.map(&:id)} before importing."
      end
      @reading = @manifest["reading"] || planned_reading
      verify_reading_inventory
      @manifest["reading"] = @reading
      @scenario_manifest.save_scenario
      import_library_entries
      import_reading_sessions
      reconcile_saved_reading
    end
  end

  def reconcile_reading
    with_reading_context do
      @reading = @manifest["reading"]
      raise ActivityError, "Replay the reading inventory before reconciling jobs." unless @reading

      reconcile_saved_reading
    end
  end

  private

  def with_reading_context
    raise ActivityError, "Scenario reading writes are only available in development" unless Rails.env.development?

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      load_verified_references
      load_reading_rows
      yield
    end
  rescue DevelopmentReadingScenarioManifest::ManifestError => error
    raise ActivityError, error.message
  end

  def load_reading_rows
    @library_rows = UserBook.where(user_id: @users.values.map(&:id)).to_a
    @session_rows = ReadingSession.where(user_id: @users.values.map(&:id)).to_a
    @page_totals = @session_rows.group_by { |row| [ row.user_id, row.book_id ] }.transform_values { |rows| rows.sum(&:pages_read) }
  end

  def reconcile_saved_reading
    work = pending_callback_work
    load_reading_rows
    verify_reading_inventory
    unless @library_matches.values.all? && @session_matches.values.all?
      raise ActivityError, "Reading replay is incomplete; resume it before checking final truth."
    end
    record_counts
    @reading["callback_work"] = work
    @reading["status"] = work.fetch("pending_count").positive? ? "awaiting_jobs" : "complete"
    verify_final_library_states if @reading.fetch("status") == "complete"
    @reading["state_counts"] = @library_matches.values.map(&:status).tally
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  def load_verified_references
    unless @manifest.dig("bootstrap", "status") == "complete" && @manifest.dig("catalog", "status") == "complete"
      raise ActivityError, "Complete bootstrap and catalog replay before importing reading activity."
    end
    user_records = @manifest.fetch("bootstrap").fetch("records").fetch("users")
    book_records = @manifest.fetch("catalog").fetch("records")
    users = User.where(id: user_records.values.map { |record| record.fetch("id") }).index_by(&:id)
    books = Book.where(id: book_records.values.map { |pair| pair.fetch("book").fetch("id") }).index_by(&:id)
    @users = @plan.fetch("users").to_h do |entry|
      identity = entry.fetch("identity")
      record = user_records.fetch(identity)
      row = users[record.fetch("id")]
      verify_reference(record, row, "user #{identity}")
      unless row.attributes.slice(*entry.fetch("attributes").keys) == entry.fetch("attributes")
        raise ActivityError, "User #{identity} (ID #{row.id}) differs from the synthetic account plan."
      end
      [ identity, row ]
    end
    @books = book_records.to_h do |key, pair|
      row = books[pair.fetch("book").fetch("id")]
      verify_reference(pair.fetch("book"), row, key)
      raise ActivityError, "Book #{key} changed its external identity." unless row.ol_work_key == key

      [ key, row ]
    end
    edition_records = book_records.values.filter_map { |pair| pair.fetch("edition") if pair.fetch("edition")["id"] }
    editions = BookEdition.where(id: edition_records.map { |record| record.fetch("id") }).index_by(&:id)
    edition_records.each { |record| verify_reference(record, editions[record.fetch("id")], "Edition #{record.fetch('id')}") }
    @edition_ids = book_records.transform_values { |pair| pair.fetch("edition")["id"] }
  end

  def verify_reference(record, row, label)
    raise ActivityError, "Recorded #{label} (ID #{record['id']}) is missing." unless row

    expected = record.fetch("expected_attributes")
    unless recorded_attributes(row).slice(*expected.keys) == expected
      raise ActivityError, "Recorded #{label} (ID #{row.id}) changed; no reading data was imported."
    end
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

  def verify_reading_inventory
    intended = planned_reading
    unless @reading.is_a?(Hash) && @reading["expected_counts"] == intended.fetch("expected_counts") && @reading["records"].is_a?(Hash)
      raise ActivityError, "Reading inventory differs from the recorded scenario plan."
    end
    intended.fetch("records").each do |group, records|
      actual = @reading.fetch("records")[group]
      unless actual.is_a?(Hash) && actual.keys.sort == records.keys.sort
        raise ActivityError, "Recorded #{group} identities differ from the reading plan."
      end
      records.each do |identity, record|
        saved = actual.fetch(identity)
        unless saved.is_a?(Hash) && saved["expected_attributes"].is_a?(Hash) && saved.fetch("expected_attributes").slice(*record.fetch("expected_attributes").keys) == record.fetch("expected_attributes")
          raise ActivityError, "Recorded #{group} #{identity} differs from its planned payload."
        end
        if group == "user_books" && saved["initial_status"] != record.fetch("initial_status")
          raise ActivityError, "Recorded library status for #{identity} changed."
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
    raise ActivityError, "Two logical reading events claim the same session; review the manifest." unless session_ids.uniq.length == session_ids.length
    verify_no_unrecorded_rows(@library_rows, @library_matches.values, "library")
    verify_no_unrecorded_rows(@session_rows, @session_matches.values + @tick_matches.values, "session")
    @library_matches.each do |identity, row|
      verify_library_status(@reading.fetch("records").fetch("user_books").fetch(identity), row) if row
    end
  end

  def match_rows(records, rows, library: false)
    by_id = rows.index_by(&:id)
    records.to_h do |identity, record|
      expected = record.fetch("expected_attributes")
      if record["id"]
        row = by_id[record.fetch("id")]
        raise ActivityError, "Recorded #{identity} (ID #{record.fetch('id')}) is missing; no automatic recreation is allowed." unless row

        verify_reading_row(record, row, identity, library: library)
      else
        matches = rows.select { |candidate| comparable_reading_attributes(candidate, library: library).slice(*expected.keys) == expected }
        if matches.length > 1
          raise ActivityError, "Ambiguous reading payload #{identity}: record IDs #{matches.map(&:id)}; no records were changed."
        end
        row = matches.first
      end
      [ identity, row ]
    end
  end

  def verify_reading_row(record, row, identity, library: false)
    expected = record.fetch("expected_attributes")
    unless comparable_reading_attributes(row, library: library).slice(*expected.keys) == expected
      raise ActivityError, "Recorded #{identity} (ID #{row.id}) changed; review before replaying."
    end
  end

  def verify_no_unrecorded_rows(rows, matches, label)
    extras = rows.map(&:id) - matches.compact.map(&:id)
    raise ActivityError, "Unrecorded #{label} rows for scenario accounts: IDs #{extras}; review without deleting data." if extras.any?
  end

  def import_library_entries
    @reading.fetch("records").fetch("user_books").each do |identity, record|
      row = @library_matches[identity]
      result = row ? "reused" : "imported"
      UserBook.transaction(requires_new: true) do
        if row
          row.lock!
          verify_reading_row(record, row, identity, library: true)
          verify_library_status(record, row)
        else
          row = UserBook.create!(record.fetch("expected_attributes").merge("status" => record.fetch("initial_status")))
        end
      end
      @library_matches[identity] = row
      record_saved_reading(record, row, result, library: true)
    rescue ActiveRecord::RecordInvalid => error
      record_reading_failure(record, identity, error)
    end
  end

  def import_reading_sessions
    @plan.fetch("reading_sessions").each do |entry|
      identity = entry.fetch("identity")
      record = @reading.fetch("records").fetch("reading_sessions").fetch(identity)
      row = @session_matches[identity]
      result = row ? "reused" : "imported"
      ReadingSession.transaction(requires_new: true) do
        if row
          row.lock!
          verify_reading_row(record, row, identity)
        else
          library_identity = "#{entry.fetch('reader')}/#{entry.fetch('work_key')}"
          library = @library_matches.fetch(library_identity)
          library.lock!
          verify_reading_row(@reading.fetch("records").fetch("user_books").fetch(library_identity), library, library_identity, library: true)
          verify_library_status(@reading.fetch("records").fetch("user_books").fetch(library_identity), library)
          row = ReadingSessionRecorder.new(@books.fetch(entry.fetch("work_key")), @users.fetch(entry.fetch("reader")), entry.fetch("attributes").merge("book_edition_id" => @edition_ids.fetch(entry.fetch("work_key")))).record
          raise ActiveRecord::RecordInvalid, row unless row.persisted?
        end
      end
      @session_matches[identity] = row
      @page_totals[[ row.user_id, row.book_id ]] = @page_totals.fetch([ row.user_id, row.book_id ], 0) + row.pages_read if result == "imported"
      record_saved_reading(record, row, result)
    rescue ActiveRecord::RecordInvalid => error
      record_reading_failure(record, identity, error)
    end
  end

  def record_reading_failure(record, identity, error)
    record["result"] = "failed"
    record["errors"] = error.record.errors.full_messages
    @scenario_manifest.save_scenario
    raise ActivityError, "Reading record #{identity} failed validation: #{record.fetch('errors').join(', ')}"
  end

  def record_saved_reading(record, row, result, library: false)
    record["id"] = row.id
    record["result"] = result
    record.delete("errors")
    record["expected_attributes"] = comparable_reading_attributes(row, library: library)
    @scenario_manifest.save_scenario
  end

  def verify_library_status(record, row)
    initial = record.fetch("initial_status")
    allowed = initial == "reading" ? [ "reading", derived_status(row) ].uniq : [ initial ]
    raise ActivityError, "Library row ID #{row.id} has an unexpected status #{row.status}; no automatic overwrite is allowed." unless allowed.include?(row.status)
  end

  def derived_status(row)
    pages = @books.values.find { |book| book.id == row.book_id }.total_pages
    total = @page_totals.fetch([ row.user_id, row.book_id ], 0)
    pages && total >= pages ? "finished" : "reading"
  end

  def verify_final_library_states
    @library_matches.each do |identity, row|
      record = @reading.fetch("records").fetch("user_books").fetch(identity)
      expected = record.fetch("initial_status") == "reading" ? derived_status(row) : record.fetch("initial_status")
      raise ActivityError, "Progress jobs did not reconcile library row ID #{row.id}: expected #{expected}, found #{row.status}." unless row.status == expected
    end
    unless (@library_matches.values.map(&:status).uniq & UserBook::STATUSES).length == 3
      raise ActivityError, "Final library states do not include all three required states; review source page totals and activity."
    end
  end

  def pending_callback_work
    actor_gids = @users.values.map { |user| user.to_global_id.to_s }
    club_ids = BookClub.where(current_book_id: @books.values.map(&:id)).pluck(:id)
    relevant = ->(name, arguments) {
      if name == "BookClubLeaderboardJob"
        club_ids.include?(arguments.first)
      else
        CALLBACK_JOBS.include?(name) && arguments.first.is_a?(Hash) && actor_gids.include?(arguments.first["_aj_globalid"])
      end
    }
    adapter = ActiveJob::Base.queue_adapter
    if adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)
      pending = adapter.enqueued_jobs.count { |job| relevant.call(job.fetch("job_class"), job.fetch("arguments")) }
      { "pending_count" => pending, "failed_job_ids" => [] }
    elsif adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
      pending = SolidQueue::Job.where(class_name: CALLBACK_JOBS, finished_at: nil).includes(:failed_execution)
        .select { |job| relevant.call(job.class_name, job.arguments.fetch("arguments")) }
      { "pending_count" => pending.length, "failed_job_ids" => pending.select(&:failed_execution).map(&:id) }
    else
      raise ActivityError, "Reading reconciliation requires the configured Solid Queue worker or the explicit test adapter."
    end
  end

  def record_counts
    counts = {
      "user_books" => @library_matches.values.compact.length,
      "baseline_reading_sessions" => @session_matches.values.compact.length,
      "reading_sessions" => @session_matches.values.compact.length + @tick_matches.values.compact.length
    }
    unless counts.fetch("user_books") == 150 && counts.fetch("baseline_reading_sessions") == 300
      raise ActivityError, "Unexpected reading inventory: #{counts.inspect}"
    end
    @reading["actual_counts"] = counts
  end

  def comparable_reading_attributes(row, library: false)
    attributes = recorded_attributes(row)
    library ? attributes.except("status") : attributes
  end

  def recorded_attributes(row)
    JSON.parse(row.attributes.except("id", "updated_at", "remember_created_at", "reset_password_token", "reset_password_sent_at").to_json)
  end
end
