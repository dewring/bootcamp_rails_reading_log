class Reaction < ApplicationRecord
  include ReactionBehavior

  belongs_to :book
  self.reaction_target_name = :book

  validates :user_id, uniqueness: { scope: :book_id }
end
