require "test_helper"

class DevelopmentReadingScenarioCoverPreviews::JobsTest < ActiveSupport::TestCase
  setup do
    @book = books(:refactoring)
    @monitor = DevelopmentReadingScenarioCoverPreviews::Jobs.new(adapter: ActiveJob::QueueAdapters::SolidQueueAdapter.new)
    @queued = []
  end

  teardown do
    @queued.each { |job| job.destroy! if job.persisted? }
  end

  test "native failed cover jobs report their IDs without treating the image as downloaded" do
    job = CoverAttachJob.new(@book, 42)
    queued = enqueue_native(job)
    queued.ready_execution.destroy!
    queued.failed_with(StandardError.new("Synthetic download failure"))

    report = @monitor.observe_job({ "job_id" => job.job_id, "cover_id" => 42 }, @book)

    assert_equal({ "job_status" => "failed", "failed_job_ids" => [ queued.id ] }, report)
    assert_not_requested :any, /https?:/
  end

  test "native retry history with one logical job ID remains pending until all attempts finish" do
    job = CoverAttachJob.new(@book, 42)
    original = enqueue_native(job)
    finish_native(original)
    retry_job = CoverAttachJob.new(@book, 42)
    retry_job.job_id = job.job_id
    retry_record = enqueue_native(retry_job)
    record = { "job_id" => job.job_id, "cover_id" => 42 }

    assert_equal "pending", @monitor.observe_job(record, @book).fetch("job_status")
    finish_native(retry_record)
    assert_equal "finished", @monitor.observe_job(record, @book).fetch("job_status")
    assert_not_requested :any, /https?:/
  end

  test "an unexpected cover ID bound to the recorded job identity is refused" do
    job = CoverAttachJob.new(@book, 43)
    enqueue_native(job)

    error = assert_raises(DevelopmentReadingScenarioCoverPreviews::PreviewError) do
      @monitor.observe_job({ "job_id" => job.job_id, "cover_id" => 42 }, @book)
    end
    assert_includes error.message, "unexpected payload"
  end

  private

  def enqueue_native(job)
    record = SolidQueue::Job.enqueue(job)
    @queued.push(record)
    record
  end

  def finish_native(record)
    record.ready_execution.destroy!
    record.update!(finished_at: Time.current)
  end
end
