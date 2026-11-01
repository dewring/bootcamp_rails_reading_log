class DevelopmentReadingScenarioActivity
  class ActivityError < StandardError; end

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
      @reading = @inventory.reading
      @inventory.verify_reading
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

  def preflight_reading(allow_incomplete: false)
    with_reading_context do
      @reading = @manifest["reading"]
      raise ActivityError, "Replay the reading inventory before preflighting saved reading activity." unless @reading

      @inventory.verify_reading
      unless allow_incomplete || @inventory.complete?
        raise ActivityError, "Reading replay is incomplete; resume it before importing community data."
      end
      @reading.deep_dup
    end
  end

  private

  def with_reading_context
    raise ActivityError, "Scenario reading writes are only available in development" unless Rails.env.development?

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      @references = References.new(plan: @plan, manifest: @manifest).load_references
      @inventory = Inventory.new(plan: @plan, manifest: @manifest, references: @references)
      yield
    end
  rescue DevelopmentReadingScenarioManifest::ManifestError => error
    raise ActivityError, error.message
  end

  def reconcile_saved_reading
    work = CallbackJobs.new(users: @references.users, books: @references.books).pending_work
    @inventory.verify_reading
    unless @inventory.complete?
      raise ActivityError, "Reading replay is incomplete; resume it before checking final truth."
    end
    @reading["actual_counts"] = @inventory.counts
    @reading["callback_work"] = work
    @reading["status"] = work.fetch("pending_count").positive? ? "awaiting_jobs" : "complete"
    @inventory.verify_final_library_states if @reading.fetch("status") == "complete"
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
          @inventory.verify_library_entry(record, row, identity)
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
          @inventory.verify_reading_session(record, row, identity)
        else
          library_identity = "#{entry.fetch('reader')}/#{entry.fetch('work_key')}"
          library = @inventory.library_matches.fetch(library_identity)
          library.lock!
          @inventory.verify_library_entry(@reading.fetch("records").fetch("user_books").fetch(library_identity), library, library_identity)
          row = ReadingSessionRecorder.new(@references.books.fetch(entry.fetch("work_key")), @references.users.fetch(entry.fetch("reader")), entry.fetch("attributes").merge("book_edition_id" => @references.edition_ids.fetch(entry.fetch("work_key")))).record
          raise ActiveRecord::RecordInvalid, row unless row.persisted?
        end
      end
      @inventory.remember_session(identity, row, imported: result == "imported")
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
    record["expected_attributes"] = @inventory.snapshot_attributes(row, library: library)
    @scenario_manifest.save_scenario
  end
end
