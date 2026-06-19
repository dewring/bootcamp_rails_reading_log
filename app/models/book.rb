class Book < ApplicationRecord
  # 1. Attachments
  has_one_attached :cover_image

  # 2. Validations
  validates :title, presence: true
  validates :author, presence: true

  # 3. Associations
  has_many :user_books, dependent: :destroy
  has_many :users, through: :user_books
  has_many :reading_sessions, dependent: :destroy
  has_many :book_genres, dependent: :destroy
  has_many :genres, through: :book_genres
  has_many :reviews, dependent: :destroy

  # 4. Scopes
  scope :most_read, -> {
    left_joins(:reading_sessions)
      .group(:id)
      .order("COUNT(reading_sessions.id) DESC")
  }

  # 5. Instance methods
  def total_pages_read
    reading_sessions.sum(:pages_read)
  end
end
