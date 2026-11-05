class ReviewReactionPolicy < ReactionPolicy
  private

  def reaction_target
    record.review
  end
end
