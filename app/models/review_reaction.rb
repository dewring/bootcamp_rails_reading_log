class ReviewReaction < ApplicationRecord
  include ReactionBehavior

  belongs_to :review
  self.reaction_target_name = :review

  validates :user_id, uniqueness: { scope: :review_id }
end
