class DevelopmentReadingScenarioCoverPreviews
  class PreviewError < StandardError; end

  def initialize(snapshot:, books:, manifest:, scenario_manifest:)
    @snapshot = snapshot
    @books = books
    @manifest = manifest
    @scenario_manifest = scenario_manifest
  end

  def prepare_previews
    plan = Plan.new(snapshot: @snapshot, books: @books).build_previews(missing_work_key: @manifest.dig("cover_previews", "missing_case", "work_key"))
    @previews = @manifest["cover_previews"] || plan.deep_dup
    verify_preview_plan(plan)
    @manifest["cover_previews"] = @previews
    @scenario_manifest.save_scenario
    @previews.fetch("records").each do |key, record|
      book = @books.fetch(key)
      record["cover_attached"] = book.cover_image.attached?
      record["status"] = "attached" if record.fetch("cover_attached")
      record.except!("job_status", "failed_job_ids", "notice")
      next unless record.fetch("status") == "planned"

      # Persist intent before enqueueing; an interrupted request must not be sent twice.
      record["status"] = "requested"
      @scenario_manifest.save_scenario
      job = CoverAttachJob.perform_later(book, record.fetch("cover_id"))
      record["job_id"] = job.job_id
      record["status"] = "queued"
      @scenario_manifest.save_scenario
    end
    records = @previews.fetch("records").values
    @previews["actual_counts"] = { "selected" => records.length, "statuses" => records.map { |record| record.fetch("status") }.tally,
      "source_unavailable" => @previews.fetch("source_unavailable_work_keys").length }
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  private

  def verify_preview_plan(plan)
    selected = @previews.fetch("records").transform_values { |record| record.slice("book_id", "cover_id") }
    intended = plan.fetch("records").transform_values { |record| record.slice("book_id", "cover_id") }
    unless selected == intended && @previews.values_at("limit", "missing_case", "source_unavailable_work_keys") == plan.values_at("limit", "missing_case", "source_unavailable_work_keys")
      raise PreviewError, "Recorded preview selection differs from the captured catalog or exceeds its fixed budget."
    end
  end
end
