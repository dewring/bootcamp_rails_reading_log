class DevelopmentReadingScenarioCoverPreviews
  class PreviewError < StandardError; end

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    as_of: DevelopmentReadingScenarioPlan.default_reference_time)
    @snapshot_path = Pathname.new(snapshot_path)
    @as_of = as_of
    @scenario_manifest = DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
  end

  def prepare_previews
    with_preview_context do
      refresh_preview_states
      @manifest["cover_previews"] = @previews
      @scenario_manifest.save_scenario
      @previews.fetch("records").each do |key, record|
        next unless record.fetch("status") == "planned"

        # Save intent before enqueueing so an interrupted request is not sent twice.
        record["status"] = "requested"
        @scenario_manifest.save_scenario
        job = CoverAttachJob.perform_later(@books.fetch(key), record.fetch("cover_id"))
        record["job_id"] = job.job_id
        record["status"] = "queued"
        @scenario_manifest.save_scenario
      end
      save_preview_report
    end
  end

  def reconcile_previews
    with_preview_context(require_saved: true) { save_preview_report }
  end

  private

  def with_preview_context(require_saved: false)
    raise PreviewError, "Cover preview setup is only available in development" unless Rails.env.development?

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      raise PreviewError, "Replay the catalog before preparing cover previews." unless @manifest.dig("catalog", "status") == "complete"
      raise PreviewError, "Prepare cover previews before reconciling them." if require_saved && !@manifest["cover_previews"]

      OpenLibraryCatalogReplay.new(snapshot_path: @snapshot_path, as_of: @as_of, manifest: @scenario_manifest).preflight_catalog
      ids = @manifest.fetch("catalog").fetch("records").values.map { |pair| pair.fetch("book").fetch("id") }
      @books = Book.where(id: ids).with_attached_cover_image.index_by(&:ol_work_key)
      plan = Plan.new(snapshot: JSON.parse(@snapshot_path.read), books: @books).build_previews(missing_work_key: @manifest.dig("cover_previews", "missing_case", "work_key"))
      @previews = @manifest["cover_previews"] || plan.deep_dup
      verify_preview_plan(plan)
      yield
    end
  rescue DevelopmentReadingScenarioManifest::ManifestError, OpenLibraryCatalogPreflight::PreflightError, OpenLibraryCatalogReplay::ReplayError => error
    raise PreviewError, error.message
  end

  def verify_preview_plan(plan)
    selected = @previews.fetch("records").transform_values { |record| record.slice("book_id", "cover_id") }
    intended = plan.fetch("records").transform_values { |record| record.slice("book_id", "cover_id") }
    unless selected == intended && @previews.values_at("limit", "missing_case", "source_unavailable_work_keys") == plan.values_at("limit", "missing_case", "source_unavailable_work_keys")
      raise PreviewError, "Recorded preview selection differs from the captured catalog or exceeds its fixed budget."
    end
  end

  def refresh_preview_states
    @previews.fetch("records").each do |key, record|
      record["cover_attached"] = @books.fetch(key).cover_image.attached?
      record["status"] = "attached" if record.fetch("cover_attached")
      record.except!("job_status", "failed_job_ids", "notice")
    end
  end

  def save_preview_report
    @books = Book.where(id: @books.values.map(&:id)).with_attached_cover_image.index_by(&:ol_work_key)
    if @books.fetch(@previews.fetch("missing_case").fetch("work_key")).cover_image.attached?
      raise PreviewError, "The reserved missing-cover case now has an image; no attachment was removed automatically."
    end
    refresh_preview_states
    records = @previews.fetch("records").values
    @previews["actual_counts"] = { "selected" => records.length, "statuses" => records.map { |record| record.fetch("status") }.tally,
      "source_unavailable" => @previews.fetch("source_unavailable_work_keys").length }
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end
end
