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
      return @manifest.deep_dup if @tick.fetch("status") == "complete"

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
    raise TickError, "Scenario ticks are only available in development" unless Rails.env.development?
    raise TickError, "Supported named tick: #{Plan::NAME}." unless name == Plan::NAME

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @baseline = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      unless @manifest["baseline"] && @manifest.dig("community", "status") == "saved"
        raise TickError, "Seed the complete baseline with db:seed before advancing a tick."
      end
      @bootstrap.preflight_bootstrap
      @catalog.preflight_catalog
      planned = Plan.new(baseline: @baseline, manifest: @manifest, as_of: @as_of).build_tick
      @tick = @manifest.dig("ticks", name) || planned.deep_dup
      @inventory = Inventory.new(planned: planned, tick: @tick)
      @inventory.verify_tick
      @reading.preflight_reading
      @community.preflight_community
      @references = DevelopmentReadingScenarioActivity::References.new(manifest: @manifest).load_references
      @users = @references.users.values.index_by(&:id)
      @books = @references.books.values.index_by(&:id)
      yield
    end
  rescue DevelopmentReadingScenarioManifest::ManifestError, OpenLibraryCatalogPreflight::PreflightError,
    DevelopmentReadingScenarioBootstrap::BootstrapError, OpenLibraryCatalogReplay::ReplayError,
    DevelopmentReadingScenarioActivity::ActivityError, DevelopmentReadingScenarioCommunity::CommunityError => error
    raise TickError, error.message
  end

  def import_sessions
    @tick.fetch("reading_sessions").each do |identity, record|
      row = @inventory.matches.fetch("reading_sessions")[identity]
      result = row ? "reused" : "imported"
      ReadingSession.transaction(requires_new: true) do
        if row
          row.lock!
        else
          library_id = record.fetch("library_identity")
          library_record = @manifest.fetch("reading").fetch("records").fetch("user_books").fetch(library_id)
          UserBook.lock.find(library_record.fetch("id"))
          attributes = record.fetch("expected_attributes")
          row = ReadingSessionRecorder.new(@books.fetch(attributes.fetch("book_id")), @users.fetch(attributes.fetch("user_id")), attributes.except("user_id", "book_id")).record
          raise ActiveRecord::RecordInvalid, row unless row.persisted?
        end
      end
      @inventory.checkpoint_saved_record("reading_sessions", identity, row, result)
      @scenario_manifest.save_scenario
    rescue ActiveRecord::RecordInvalid => error
      record_failure(record, identity, error)
    end
  end

  def import_posts
    @tick.fetch("club_messages").each do |identity, record|
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
      record_failure(record, identity, error)
    end
  end

  def record_tick_result
    @reading.reconcile_reading
    club_ids = @manifest.fetch("community").fetch("records").fetch("book_clubs").values.map { |record| record.fetch("id") }
    totals = { "reading_sessions" => @manifest.dig("reading", "actual_counts", "reading_sessions"),
      "club_messages" => ClubMessage.where(book_club_id: club_ids).count }
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

  def record_failure(record, identity, error)
    record["result"] = "failed"
    record["errors"] = error.record.errors.full_messages
    @scenario_manifest.save_scenario
    raise TickError, "Tick record #{identity} failed validation: #{record.fetch('errors').join(', ')}"
  end
end
