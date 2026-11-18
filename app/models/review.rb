class Review < ApplicationRecord
  belongs_to :user
  belongs_to :book
  has_many :reactions, class_name: "ReviewReaction", dependent: :destroy

  validates :rating, inclusion: { in: 0..5, message: "must be selected (0 to 5 stars)" }
  validates :user_id, uniqueness: { scope: :book_id }

  scope :matching_text, ->(text) {
    return all if text.blank?

    query = "%#{sanitize_sql_like(text.to_s.strip)}%"
    joins(:user, :book).where(
      "users.nickname ILIKE :query OR books.title ILIKE :query OR books.author ILIKE :query OR reviews.body ILIKE :query",
      query: query
    )
  }
end
