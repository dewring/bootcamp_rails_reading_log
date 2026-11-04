class ReviewReaction < ApplicationRecord
  include ReactionBehavior

  belongs_to :review

  validates :user_id, uniqueness: { scope: :review_id }
end
