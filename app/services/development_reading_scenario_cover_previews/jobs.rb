class DevelopmentReadingScenarioCoverPreviews::Jobs
  def initialize(adapter: ActiveJob::Base.queue_adapter)
    @adapter = adapter
    unless @adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter) || @adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
      raise DevelopmentReadingScenarioCoverPreviews::PreviewError, "Cover preview setup requires Solid Queue or the explicit test adapter."
    end
  end

  def observe_job(record, book)
    jobs = matching_jobs(record.fetch("job_id"))
    return { "job_status" => "not_found", "failed_job_ids" => [] } if jobs.empty?

    expected = [ { "_aj_globalid" => book.to_global_id.to_s }, record.fetch("cover_id") ]
    unless jobs.all? { |job| job.fetch("job_class") == "CoverAttachJob" && job.fetch("arguments") == expected }
      raise DevelopmentReadingScenarioCoverPreviews::PreviewError, "Cover job #{record.fetch('job_id')} has an unexpected payload; no automatic replacement is allowed."
    end
    statuses = jobs.map { |job| job.fetch("job_status") }
    status = statuses.include?("pending") ? "pending" : (statuses.include?("failed") ? "failed" : "finished")
    { "job_status" => status, "failed_job_ids" => jobs.flat_map { |job| job.fetch("failed_job_ids") } }
  end

  def enqueue_preview(record, book)
    job = CoverAttachJob.new(book, record.fetch("cover_id"))
    job.job_id = record.fetch("job_id")
    unless job.enqueue
      raise DevelopmentReadingScenarioCoverPreviews::PreviewError, "Cover job #{job.job_id} was not enqueued; inspect its queue state before retrying."
    end
    record["provider_job_id"] = job.provider_job_id
  end

  private

  def matching_jobs(id)
    if @adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)
      pending = @adapter.enqueued_jobs.select { |job| job["job_id"] == id }.map do |job|
        job.merge("job_status" => "pending", "failed_job_ids" => [])
      end
      performed = @adapter.performed_jobs.select { |job| job["job_id"] == id }.map do |job|
        job.merge("job_status" => "finished", "failed_job_ids" => [])
      end
      pending + performed
    else
      SolidQueue::Job.where(active_job_id: id).includes(:failed_execution).map do |job|
        { "job_class" => job.class_name, "arguments" => job.arguments.fetch("arguments"),
          "job_status" => job.failed_execution ? "failed" : (job.finished_at ? "finished" : "pending"),
          "failed_job_ids" => job.failed_execution ? [ job.id ] : [] }
      end
    end
  end
end
