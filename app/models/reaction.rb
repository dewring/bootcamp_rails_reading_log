class Reaction < ApplicationRecord
  include ReactionBehavior

  belongs_to :book
  self.reaction_target_name = :book

  validates :user_id, uniqueness: { scope: :book_id }

  after_commit :expire_trending_ranking, if: -> { destroyed? || saved_change_to_kind? || saved_change_to_updated_at? }

  private

  def expire_trending_ranking
    Book.expire_trending_cache
  end
end
