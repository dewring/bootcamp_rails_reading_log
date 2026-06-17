class Book < ApplicationRecord
  has_one_attached :cover_image

  validates :title, presence: true
  validates :author, presence: true

  has_many :user_books, dependent: :destroy
  has_many :users, through: :user_books
  has_many :reading_sessions, dependent: :destroy
  has_many :book_genres, dependent: :destroy
  has_many :genres, through: :book_genres

  def total_pages_read
    reading_sessions.sum(:pages_read)
  end
end
