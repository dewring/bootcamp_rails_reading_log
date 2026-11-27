class DevelopmentReadingScenarioCoverPreviews
  class PreviewError < StandardError; end

  def initialize(snapshot:, books:, manifest:, scenario_manifest:)
    @snapshot = snapshot
    @books = books
    @manifest = manifest
    @scenario_manifest = scenario_manifest
  end

  def prepare_previews
    previous = @manifest["cover_previews"]
    recorded_ids = previous&.fetch("records")&.transform_values { |entry| entry["book_id"] } || {}
    missing = previous&.fetch("missing_case")
    recorded_ids[missing.fetch("work_key")] = missing["book_id"] if missing
    plan = Plan.new(snapshot: @snapshot, books: @books).build_previews(
      missing_work_key: missing&.fetch("work_key"), recorded_ids: recorded_ids
    )
    @previews = @manifest["cover_previews"] || plan.deep_dup
    verify_preview_plan(plan)
    @manifest["cover_previews"] = @previews
    @previews["unavailable_book_work_keys"] = @snapshot.fetch("selected").map { |entry| entry.fetch("work_key") } - @books.keys
    @scenario_manifest.save_scenario(@manifest)
    @previews.fetch("records").each do |key, record|
      book = @books[key]
      unless book
        record["skip_reason"] = "book_unavailable"
        record["cover_attached"] = false
        next
      end

      record["book_id"] ||= book.id
      record.delete("skip_reason")
      record["cover_attached"] = book.cover_image.attached?
      record["status"] = "attached" if record.fetch("cover_attached")
      record.except!("job_status", "failed_job_ids", "notice")
      next unless record.fetch("status") == "planned"

      # Persist intent before enqueueing; an interrupted request must not be sent twice.
      record["status"] = "requested"
      @scenario_manifest.save_scenario(@manifest)
      job = CoverAttachJob.perform_later(book, record.fetch("cover_id"))
      record["job_id"] = job.job_id
      record["status"] = "queued"
      @scenario_manifest.save_scenario(@manifest)
    end
    records = @previews.fetch("records").values
    statuses = records.map { |record| record["skip_reason"] ? "skipped" : record.fetch("status") }
    @previews["actual_counts"] = { "selected" => records.length, "statuses" => statuses.tally,
      "source_unavailable" => @previews.fetch("source_unavailable_work_keys").length }
    @scenario_manifest.save_scenario(@manifest)
    @manifest.deep_dup
  end

  private

  def verify_preview_plan(plan)
    selected = @previews.fetch("records").to_h do |key, record|
      attributes = record.slice("book_id", "cover_id")
      attributes["book_id"] ||= @books[key]&.id
      [ key, attributes ]
    end
    intended = plan.fetch("records").transform_values { |record| record.slice("book_id", "cover_id") }
    missing = @previews.fetch("missing_case")
    missing["book_id"] ||= @books[missing.fetch("work_key")]&.id
    unless selected == intended && @previews.values_at("limit", "missing_case", "source_unavailable_work_keys") == plan.values_at("limit", "missing_case", "source_unavailable_work_keys")
      raise PreviewError, "Recorded preview selection differs from the captured catalog or exceeds its fixed budget."
    end
  end
end
