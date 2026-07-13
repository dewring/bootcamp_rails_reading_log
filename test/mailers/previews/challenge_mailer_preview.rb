class ChallengeMailerPreview < ActionMailer::Preview
  def streak_at_risk
    ChallengeMailer.streak_at_risk(User.find_by!(nickname: "chii"))
  end

  def milestone_reached
    user = User.find_by!(nickname: "chii")
    user_challenge = user.user_challenges.first!
    ChallengeMailer.milestone_reached(user, user_challenge)
  end

  def challenge_completed
    user = User.find_by!(nickname: "chii")
    user_challenge = user.user_challenges.first!
    ChallengeMailer.challenge_completed(user, user_challenge)
  end
end
