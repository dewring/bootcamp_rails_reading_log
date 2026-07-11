require "test_helper"

class ChallengeMailerTest < ActionMailer::TestCase
  test "streak_at_risk: sends a fixed warning subject to the user's email" do
    user = users(:jaina)
    challenge = Challenge.create!(
      title: "streak 7 days", goal_type: "streak_days", goal_value: 7,
      starts_at: 7.days.ago, ends_at: 7.days.from_now
    )
    user.user_challenges.create!(challenge: challenge, status: "in_progress", progress: 0)

    mail = ChallengeMailer.streak_at_risk(user)

    assert_equal "Your streak is about to break", mail.subject
    assert_equal [ user.email ], mail.to
    assert_match "#{challenge.title}", mail.body.encoded
  end

  test "milestone_reached: builds subject from progress percentage and challenge title" do
    user = users(:jaina)
    challenge = Challenge.create!(
      title: "streak 7 days", goal_type: "streak_days", goal_value: 7,
      starts_at: 7.days.ago, ends_at: 7.days.from_now
    )
    user_challenge = user.user_challenges.create!(challenge: challenge, status: "in_progress", progress: 4)

    mail = ChallengeMailer.milestone_reached(user, user_challenge)

    assert_equal "You're #{user_challenge.progress}% through #{challenge.title}!", mail.subject
    assert_equal [ user.email ], mail.to
    assert_match "You're #{user_challenge.progress}% through #{challenge.title}!", mail.body.encoded
  end

  test "challenge_completed: builds subject from challenge title on completion" do
    user = users(:jaina)
    challenge = Challenge.create!(
      title: "streak 7 days", goal_type: "streak_days", goal_value: 7,
      starts_at: 7.days.ago, ends_at: 7.days.from_now
    )
    user_challenge = user.user_challenges.create!(challenge: challenge, status: "completed")

    mail = ChallengeMailer.challenge_completed(user, user_challenge)

    assert_equal "You've completed #{challenge.title}!", mail.subject
    assert_equal [ user.email ], mail.to
    assert_match "You've completed #{challenge.title}!", mail.body.encoded
  end
end
