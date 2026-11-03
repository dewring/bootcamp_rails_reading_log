class DevelopmentReadingScenarioActivity
  class ActivityError < StandardError; end

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    as_of: DevelopmentReadingScenarioPlan.default_reference_time, manifest: nil)
    @snapshot_path = snapshot_path
    @as_of = as_of
    @scenario_manifest = manifest || DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
  end

  def replay_reading
    with_reading_context do
      @reading = @inventory.reading
      @inventory.verify_reading
      @manifest["reading"] = @reading
      @scenario_manifest.save_scenario
      import_library_entries
      import_reading_sessions
      record_reading_totals
    end
  end

  def reconcile_reading
    with_reading_context do
      @reading = @manifest.fetch("reading")
      @inventory.verify_reading
      record_reading_totals
    end
  end

  def preflight_reading
    with_reading_context do
      @reading = @manifest.fetch("reading")
      @inventory.verify_reading
      @reading.deep_dup
    end
  end

  private

  def with_reading_context
    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      @references = References.new(manifest: @manifest).load_references
      @inventory = Inventory.new(plan: @plan, manifest: @manifest, references: @references)
      yield
    end
  end

  def record_reading_totals
    @reading["actual_counts"] = @inventory.counts
    @reading.delete("callback_work")
    @reading["status"] = "complete"
    @reading["state_counts"] = @inventory.state_counts
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  def import_library_entries
    @reading.fetch("records").fetch("user_books").each do |identity, record|
      row = @inventory.library_matches[identity]
      result = row ? "reused" : "imported"
      UserBook.transaction(requires_new: true) do
        if row
          row.lock!
        else
          row = UserBook.create!(record.fetch("expected_attributes").merge("status" => record.fetch("initial_status")))
        end
      end
      @inventory.remember_library_entry(identity, row)
      record_saved_reading(record, row, result, library: true)
    rescue ActiveRecord::RecordInvalid => error
      record_reading_failure(record, identity, error)
    end
  end

  def import_reading_sessions
    @plan.fetch("reading_sessions").each do |entry|
      identity = entry.fetch("identity")
      record = @reading.fetch("records").fetch("reading_sessions").fetch(identity)
      row = @inventory.session_matches[identity]
      result = row ? "reused" : "imported"
      ReadingSession.transaction(requires_new: true) do
        if row
          row.lock!
        else
          row = record_planned_session(entry)
        end
      end
      @inventory.remember_session(identity, row)
      record_saved_reading(record, row, result)
    rescue ActiveRecord::RecordInvalid => error
      record_reading_failure(record, identity, error)
    end
  end

  def record_planned_session(entry)
    library_identity = "#{entry.fetch('reader')}/#{entry.fetch('work_key')}"
    @inventory.library_matches.fetch(library_identity).lock!
    book = @references.books.fetch(entry.fetch("work_key"))
    user = @references.users.fetch(entry.fetch("reader"))
    attributes = entry.fetch("attributes").merge("book_edition_id" => @references.edition_ids.fetch(entry.fetch("work_key")))
    session = ReadingSessionRecorder.new(book, user, attributes).record
    raise ActiveRecord::RecordInvalid, session unless session.persisted?

    session
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
    record["expected_attributes"] = @inventory.snapshot_attributes(row, library: library)
    @scenario_manifest.save_scenario
  end
end
