class ChallengeProgressJob < ApplicationJob
  include SemanticLogger::Loggable
  include ActiveJob::Continuable

  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(user)
    logger.measure_info("Recalculating challenge progress", payload: { user_id: user.id }) do
      step :recalculate_user_challenges, start: 0 do |step|
        user.user_challenges.includes(:challenge, :user)
            .where(status: [ "active", "in_progress" ])
            .find_each(start: step.cursor) do |user_challenge|
              ChallengeProgressCalculator.new(user_challenge).recalculate
              step.advance! from: user_challenge.id
            end
      end
    end
  end
end
