class DevelopmentReadingScenarioActivity::CallbackJobs
  CALLBACK_JOBS = [ "BookProgressJob", "BadgeAwardJob", "ChallengeProgressJob", "BookClubLeaderboardJob" ].freeze

  def initialize(users:, books:)
    @users = users
    @books = books
  end

  def pending_work
    actor_gids = @users.values.map { |user| user.to_global_id.to_s }
    club_ids = BookClub.where(current_book_id: @books.values.map(&:id)).pluck(:id)
    relevant = ->(name, arguments) {
      if name == "BookClubLeaderboardJob"
        club_ids.include?(arguments.first)
      else
        CALLBACK_JOBS.include?(name) && arguments.first.is_a?(Hash) && actor_gids.include?(arguments.first["_aj_globalid"])
      end
    }
    adapter = ActiveJob::Base.queue_adapter
    if adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)
      pending = adapter.enqueued_jobs.count { |job| relevant.call(job.fetch("job_class"), job.fetch("arguments")) }
      { "pending_count" => pending, "failed_job_ids" => [] }
    elsif adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
      pending = SolidQueue::Job.where(class_name: CALLBACK_JOBS, finished_at: nil).includes(:failed_execution)
        .select { |job| relevant.call(job.class_name, job.arguments.fetch("arguments")) }
      { "pending_count" => pending.length, "failed_job_ids" => pending.select(&:failed_execution).map(&:id) }
    else
      raise DevelopmentReadingScenarioActivity::ActivityError, "Reading reconciliation requires the configured Solid Queue worker or the explicit test adapter."
    end
  end
end
