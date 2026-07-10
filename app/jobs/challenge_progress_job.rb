class ChallengeProgressJob < ApplicationJob
  include SemanticLogger::Loggable

  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(user)
    logger.measure_info("Recalculating challenge progress", payload: { user_id: user.id }) do
      user.user_challenges.includes(:challenge, :user)
          .where(status: [ "active", "in_progress" ])
          .find_each do |user_challenge|
        recalculate(user_challenge)
      end
    end
  end

  private

  def recalculate(user_challenge)
    challenge = user_challenge.challenge

    case challenge.goal_type
    when "books_total"
      count = user_challenge.user.user_books
                .where(status: "finished")
                .where("updated_at >= ?", user_challenge.created_at)
                .count
      finalize_count_based(user_challenge, challenge, count)

    when "streak_days"
      streak = current_streak(user_challenge.user)
      finalize_count_based(user_challenge, challenge, streak)

    when "pages_per_day"
      finalize_pages_per_day(user_challenge, challenge)
    end
  end

  def finalize_count_based(user_challenge, challenge, count)
    percentage = percentage_for(count, challenge.goal_value)
    deadline_passed = Date.current > challenge.ends_at.to_date

    if count >= challenge.goal_value
      update_if_changed(user_challenge, status: :completed, progress: 100)
    elsif deadline_passed
      update_if_changed(user_challenge, status: :failed, progress: percentage)
    else
      new_status = percentage.positive? ? :in_progress : :active
      update_if_changed(user_challenge, status: new_status, progress: percentage)
    end
  end

  def finalize_pages_per_day(user_challenge, challenge)
    fully_ended_days = challenge.starts_at.to_date...Date.current
    total_days = fully_ended_days.count
    met_days = 0
    failed_day_found = false

    fully_ended_days.each do |day|
      pages = ReadingSession.where(user: user_challenge.user, read_on: day).sum(:pages_read)
      if pages >= challenge.goal_value
        met_days += 1
      else
        failed_day_found = true
      end
    end

    percentage = total_days.positive? ? ((met_days.to_f / total_days) * 100).round : 0
    deadline_passed = Date.current > challenge.ends_at.to_date

    if failed_day_found
      update_if_changed(user_challenge, status: :failed, progress: percentage)
    elsif deadline_passed && total_days.positive? && met_days == total_days
      update_if_changed(user_challenge, status: :completed, progress: 100)
    else
      new_status = met_days.positive? ? :in_progress : :active
      update_if_changed(user_challenge, status: new_status, progress: percentage)
    end
  end

  def percentage_for(count, goal_value)
    [ ((count.to_f / goal_value) * 100).round, 100 ].min
  end

  def update_if_changed(user_challenge, status:, progress:)
    return if user_challenge.status == status.to_s && user_challenge.progress == progress

    user_challenge.update!(status: status, progress: progress)
  end

  def current_streak(user)
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
