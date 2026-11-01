require "test_helper"

class DevelopmentReadingScenarioActivity::CallbackJobsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:leika)
    @book = Book.create!(title: "Callback monitoring source", author: "A Reader")
    @club = BookClub.create!(name: "Callback monitoring club", current_book: @book)
    @monitor = DevelopmentReadingScenarioActivity::CallbackJobs.new(users: { "reader" => @user }, books: { "work" => @book })
    @queue_jobs = []
  end

  teardown do
    @queue_jobs.each { |job| job.destroy! if job.persisted? }
  end

  test "test adapter monitoring counts selected readers and clubs without executing jobs" do
    other_club = BookClub.create!(name: "Unrelated club")
    BookProgressJob.perform_later(@user, @book)
    BadgeAwardJob.perform_later(users(:jaina))
    BookClubLeaderboardJob.perform_later(@club.id)
    BookClubLeaderboardJob.perform_later(other_club.id)
    CoverAttachJob.perform_later(@book, 123)
    queued = enqueued_jobs.dup

    assert_no_difference "UserBadge.count" do
      assert_equal({ "pending_count" => 2, "failed_job_ids" => [] }, @monitor.pending_work)
    end
    assert_equal queued, enqueued_jobs
  end

  test "Solid Queue monitoring reports selected failed work and excludes finished and unrelated jobs" do
    enqueue_queue_record(BookProgressJob.new(@user, @book))
    failed = enqueue_queue_record(BadgeAwardJob.new(@user))
    failed.ready_execution.destroy!
    failed.failed_with(StandardError.new("Synthetic callback failure"))
    enqueue_queue_record(BookProgressJob.new(users(:jaina), @book))
    finished = enqueue_queue_record(ChallengeProgressJob.new(@user))
    finished.ready_execution.destroy!
    finished.update!(finished_at: Time.current)

    ActiveJob::Base.stub(:queue_adapter, ActiveJob::QueueAdapters::SolidQueueAdapter.new) do
      assert_equal({ "pending_count" => 2, "failed_job_ids" => [ failed.id ] }, @monitor.pending_work)
    end
    assert_nil failed.reload.finished_at
    assert SolidQueue::FailedExecution.exists?(job_id: failed.id)
  end

  test "unsupported queue adapters are refused instead of reporting completion" do
    ActiveJob::Base.stub(:queue_adapter, ActiveJob::QueueAdapters::InlineAdapter.new) do
      error = assert_raises(DevelopmentReadingScenarioActivity::ActivityError) { @monitor.pending_work }
      assert_includes error.message, "requires the configured Solid Queue worker"
    end
  end

  test "a selected quiet club is monitored even when it has no current book" do
    quiet = BookClub.create!(name: "Selected quiet club")
    BookClubLeaderboardJob.perform_later(quiet.id)
    monitor = DevelopmentReadingScenarioActivity::CallbackJobs.new(users: { "reader" => @user }, books: { "work" => @book }, additional_club_ids: [ quiet.id ])

    assert_equal({ "pending_count" => 1, "failed_job_ids" => [] }, monitor.pending_work)
  end

  private

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def enqueue_queue_record(job)
    record = SolidQueue::Job.enqueue(job)
    @queue_jobs.push(record)
    record
  end
end
