class DevelopmentReadingScenarioTick
  class TickError < StandardError; end

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    as_of: DevelopmentReadingScenarioPlan.default_reference_time)
    @snapshot_path = snapshot_path
    @as_of = as_of
    @scenario_manifest = DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
    dependencies = { snapshot_path: snapshot_path, as_of: as_of, manifest: @scenario_manifest }
    @bootstrap = DevelopmentReadingScenarioBootstrap.new(**dependencies)
    @catalog = OpenLibraryCatalogReplay.new(**dependencies)
    @reading = DevelopmentReadingScenarioActivity.new(**dependencies)
    @community = DevelopmentReadingScenarioCommunity.new(**dependencies)
  end

  def advance_scenario(tick:)
    with_tick_context(tick) do
      if @tick.fetch("status") == "complete"
        return @manifest.deep_dup if @tick["actual_counts"] == @inventory.saved_counts

        return record_tick_result
      end

      @manifest["ticks"] ||= {}
      @manifest.fetch("ticks")[tick] = @tick
      @scenario_manifest.save_scenario
      import_sessions
      import_posts
      record_tick_result
    end
  end

  private

  def with_tick_context(name)
    unless name.is_a?(String) && name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/)
      raise TickError, "Use a tick name of 1–64 letters, numbers, underscores or hyphens, starting with a letter or number."
    end

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path, manifest_path: @scenario_manifest.path).preflight_catalog(skip_book_conflicts: true)
      @baseline = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      unless @manifest["baseline"] && @manifest.dig("community", "status") == "saved"
        raise TickError, "Run DevelopmentReadingScenario.new.seed_scenario in the Rails console before advancing a tick."
      end
      @bootstrap.preflight_bootstrap
      @catalog.preflight_catalog
      @references = DevelopmentReadingScenarioActivity::References.new(manifest: @manifest).load_references
      @users = @references.users.values.compact.index_by(&:id)
      @books = @references.books.values.compact.index_by(&:id)
      @tick = @manifest.dig("ticks", name) || Plan.new(baseline: @baseline, manifest: @manifest, as_of: @as_of, name: name).build_tick
      @tick.fetch("reading_sessions").each_value do |record|
        if !@users.key?(record.dig("expected_attributes", "user_id"))
          record.merge!("result" => "skipped", "reason" => "account_unavailable")
        elsif !@books.key?(record.dig("expected_attributes", "book_id"))
          record.merge!("result" => "skipped", "reason" => "book_unavailable")
        end
      end
      @reading.preflight_reading
      @community.preflight_community
      reject_unavailable_tick_posts
      @inventory = Inventory.new(tick: @tick)
      @inventory.verify_tick
      reject_ticks_for_unavailable_shelves
      yield
    end
  end

  def reject_unavailable_tick_posts
    clubs = @manifest.fetch("community").fetch("records").fetch("book_clubs")
    club_ids = clubs.values.filter_map { |record| record["id"] unless record["result"] == "skipped" }.to_set
    @tick.fetch("club_messages").each_value do |record|
      unless @users.key?(record.dig("expected_attributes", "user_id"))
        record.merge!("result" => "skipped", "reason" => "account_unavailable")
        next
      end
      next if club_ids.include?(record.dig("expected_attributes", "book_club_id"))

      record.merge!("result" => "skipped", "reason" => "club_unavailable")
    end
  end

  def reject_ticks_for_unavailable_shelves
    shelves = @manifest.fetch("reading").fetch("records").fetch("user_books")
    @tick.fetch("reading_sessions").each do |identity, record|
      next if record["result"] == "skipped" || @inventory.matches.fetch("reading_sessions")[identity]

      shelf = shelves.fetch(record.fetch("library_identity"))
      if shelf["origin"] == "existing"
        record.merge!("result" => "skipped", "reason" => "existing_shelf_preserved")
      elsif shelf["result"] == "skipped"
        record.merge!("result" => "skipped", "reason" => "library_entry_unavailable")
      end
    end
  end

  def import_sessions
    @tick.fetch("reading_sessions").each do |identity, record|
      next if record["result"] == "skipped"

      row = @inventory.matches.fetch("reading_sessions")[identity]
      result = row ? "reused" : "imported"
      work_key = @books.fetch(record.dig("expected_attributes", "book_id")).ol_work_key
      if !row && @references.update_pending_session_edition(record, work_key: work_key)
        @scenario_manifest.save_scenario
      end
      ReadingSession.transaction(requires_new: true) do
        if row
          row.lock!
        else
          row = record_planned_session(record)
        end
      end
      @inventory.checkpoint_saved_record("reading_sessions", identity, row, result)
      @scenario_manifest.save_scenario
    rescue ActiveRecord::RecordInvalid => error
      record_failure(record, error)
      raise
    end
  end

  def record_planned_session(record)
    library_record = @manifest.fetch("reading").fetch("records").fetch("user_books").fetch(record.fetch("library_identity"))
    UserBook.lock.find(library_record.fetch("id"))
    attributes = record.fetch("expected_attributes")
    book = @books.fetch(attributes.fetch("book_id"))
    user = @users.fetch(attributes.fetch("user_id"))
    session = ReadingSessionRecorder.new(book, user, attributes.except("user_id", "book_id")).record
    raise ActiveRecord::RecordInvalid, session unless session.persisted?

    session
  end

  def import_posts
    @tick.fetch("club_messages").each do |identity, record|
      next if record["result"] == "skipped"

      row = @inventory.matches.fetch("club_messages")[identity]
      result = row ? "reused" : "imported"
      ClubMessage.transaction(requires_new: true) do
        if row
          row.lock!
        else
          attributes = record.fetch("expected_attributes")
          row = ClubMessage.new(attributes)
          row.user = @users.fetch(attributes.fetch("user_id"))
          row.save!
        end
      end
      @inventory.checkpoint_saved_record("club_messages", identity, row, result)
      @scenario_manifest.save_scenario
    rescue ActiveRecord::RecordInvalid => error
      record_failure(record, error)
      raise
    end
  end

  def record_tick_result
    @reading.reconcile_reading
    community = @community.preflight_community
    totals = { "reading_sessions" => @manifest.dig("reading", "actual_counts", "reading_sessions"),
      "club_messages" => community.dig("actual_counts", "club_messages_with_ticks") }
    @tick["actual_counts"] = @inventory.saved_counts
    @tick["baseline_counts"] = { "reading_sessions" => 300, "club_messages" => 80 }
    @tick["scenario_counts"] = totals
    @tick["status"] = @manifest.fetch("reading").fetch("status")
    @tick.delete("callback_work")
    @manifest.fetch("community").fetch("actual_counts")["club_messages_with_ticks"] = totals.fetch("club_messages")
    @manifest.fetch("baseline").fetch("actual_counts").merge!(totals)
    @manifest.fetch("baseline")["status"] = @tick.fetch("status")
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  def record_failure(record, error)
    record["result"] = "failed"
    record["errors"] = error.record.errors.full_messages
    @scenario_manifest.save_scenario
  end
end
