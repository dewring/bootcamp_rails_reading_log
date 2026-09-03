class Book < ApplicationRecord
  include Displayable
  include HasAttachedCoverImage

  # 1. Attachments
  serialize :subjects, coder: JSON

  # 2. Normalizations
  normalizes :title, with: ->(v) { v.titleize }
  normalizes :author, with: ->(v) { v.titleize }

  # 3. Validations
  validates :author, presence: true
  validates :title, presence: true

  # 4. Associations
  has_many :user_books, dependent: :destroy
  has_many :users, through: :user_books
  has_many :reading_sessions, dependent: :destroy
  has_many :book_genres, dependent: :destroy
  has_many :genres, through: :book_genres
  has_many :reviews, dependent: :destroy
  has_many :book_editions, dependent: :destroy

  # 5. Scopes
  scope :most_read, -> {
    left_joins(:reading_sessions)
      .group(:id)
      .order("COUNT(reading_sessions.id) DESC")
  }

  # 6. Instance methods
  def total_pages_read
    reading_sessions.sum(:pages_read)
  end

  def self.find_or_create_from_search_result(doc)
    return nil if doc["key"].blank?

    find_or_create_by(ol_work_key: doc["key"]) do |book|
      book.title  = doc["title"]
      book.author = doc["author_name"].first
    end
  end
end
