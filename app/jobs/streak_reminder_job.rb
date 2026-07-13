class StreakReminderJob < ApplicationJob
  queue_as :default

  def perform
    users_at_risk = User.joins(user_challenges: :challenge)
                        .where(user_challenges: { status: [ "active", "in_progress" ] }, challenges: { goal_type: "streak_days" })
                        .distinct
    users_at_risk.find_each do |user|
      next if ReadingSession.exists?(user: user, read_on: Date.current)
      ChallengeMailer.streak_at_risk(user).deliver_later
    end
  end
end
