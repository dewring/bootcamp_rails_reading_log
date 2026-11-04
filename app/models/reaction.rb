class Reaction < ApplicationRecord
  include ReactionBehavior

  belongs_to :book

  validates :user_id, uniqueness: { scope: :book_id }
end
