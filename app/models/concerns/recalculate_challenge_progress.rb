module RecalculateChallengeProgress
  extend ActiveSupport::Concern

  included do
    after_commit :recalculate_challenge_progress
  end

  private

  def recalculate_challenge_progress
    ChallengeProgressJob.perform_later(user)
  end
end
