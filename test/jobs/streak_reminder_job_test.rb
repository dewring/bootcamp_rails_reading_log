require "test_helper"

class StreakReminderJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "enqueues streak_at_risk for a user who hasn't logged today" do
    user = users(:jaina)
    challenge = Challenge.create!(
      title: "streak 3 days", goal_type: "streak_days", goal_value: 3,
      starts_at: 3.days.ago, ends_at: 3.days.from_now
    )
    user.user_challenges.create!(challenge: challenge, status: "in_progress", progress: 0)

    assert_enqueued_email_with ChallengeMailer, :streak_at_risk, args: [ user ] do
      StreakReminderJob.new.perform
    end
  end

  test "does not enqueue an email for a user who already logged today" do
    user = users(:jaina)
    challenge = Challenge.create!(
      title: "streak 3 days", goal_type: "streak_days", goal_value: 3,
      starts_at: 3.days.ago, ends_at: 3.days.from_now
    )
    ReadingSession.create!(user: user, book: books(:refactoring), read_on: Date.current, pages_read: 15)
    user.user_challenges.create!(challenge: challenge, status: "in_progress", progress: 0)

    assert_no_enqueued_emails do
      StreakReminderJob.new.perform
    end
  end
end
