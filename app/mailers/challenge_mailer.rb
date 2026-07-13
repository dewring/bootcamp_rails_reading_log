class ChallengeMailer < ApplicationMailer
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.challenge_mailer.streak_at_risk.subject
  #
  def streak_at_risk(user)
    @user = user
    @current_streak = ReadingSession.current_streak(@user)
    @streak_challenging = @user.user_challenges.joins(:challenge).where(status: [ "in_progress", "active" ], challenge: { goal_type: "streak_days" })

    mail to: @user.email, subject: "Your streak is about to break"
  end

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.challenge_mailer.milestone_reached.subject
  #
  def milestone_reached(user, user_challenge)
    @user = user
    @user_challenge = user_challenge
    @challenge = @user_challenge.challenge

    mail to: @user.email, subject: "You're #{@user_challenge.progress}% through #{@challenge.title}!"
  end

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.challenge_mailer.challenge_completed.subject
  #
  def challenge_completed(user, user_challenge)
    @user = user
    @user_challenge = user_challenge
    @challenge = @user_challenge.challenge

    mail to: @user.email, subject: "You've completed #{@challenge.title}!"
  end
end
