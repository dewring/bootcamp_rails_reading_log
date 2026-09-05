class ReadingMetricsJob < ApplicationJob
  include SemanticLogger::Loggable
  include ActiveJob::Continuable

  queue_as :default

  def perform
    users = User.joins(:reading_sessions).distinct

    logger.measure_info(
      "Calculating reading metrics",
      payload: { user_count: users.count }
    ) do
      step :calculate_metrics_for_users, start: 0 do |step|
        users.find_each(start: step.cursor) do |user|
          begin
            calculate_metrics(user)
          rescue => e
            logger.error("Failed to calculate metrics for user", user_id: user.id, error_message: e.message)
          end
          step.advance! from: user.id
        end
      end
    end
  end

  private

  def calculate_metrics(user)
    pages_today = ReadingSession.where(user: user, read_on: Date.current).sum(:pages_read)
    pages_this_week = ReadingSession.where(user: user, read_on: Date.current.beginning_of_week..Date.current).sum(:pages_read)
    books_in_progress = user.user_books.where(status: "reading").count
    books_finished = user.user_books.where(status: "finished").count
    current_streak = calculate_streak(user)

    metric = ReadingMetric.find_or_initialize_by(user: user)
    metric.update!(
      pages_today: pages_today,
      pages_this_week: pages_this_week,
      books_in_progress: books_in_progress,
      books_finished: books_finished,
      current_streak: current_streak,
      calculated_at: Time.current
    )
  end

  def calculate_streak(user)
    session_dates = ReadingSession.where(user: user, read_on: 90.days.ago.to_date..Date.current)
                                  .distinct.pluck(:read_on).to_set

    streak = 0
    date = Date.current
    while session_dates.include?(date)
      streak += 1
      date -= 1.day
    end
    streak
  end
end
