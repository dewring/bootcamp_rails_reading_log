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

  scope :top_book_per_genre, -> {
    ranked = joins(:genres)
      .joins("LEFT JOIN reading_sessions ON reading_sessions.book_id = books.id")
      .group(Arel.sql("books.id, genres.id"))
      .select(Arel.sql(<<~SQL.squish))
        books.*,
        ROW_NUMBER() OVER (
          PARTITION BY genres.id
          ORDER BY COUNT(reading_sessions.id) DESC, books.id ASC
        ) AS rn
      SQL

    with(ranked_books: ranked)
      .from("ranked_books AS books")
      .where(rn: 1)
  }

  scope :above_average_reads, -> {
    joins(:reading_sessions)
      .group("books.id")
      .having(Arel.sql(<<~SQL.squish))
        SUM(reading_sessions.pages_read) > (
          SELECT AVG(book_totals.total_pages)
          FROM (
            SELECT SUM(avg_sessions.pages_read) AS total_pages
            FROM books AS avg_books
            INNER JOIN reading_sessions AS avg_sessions ON avg_sessions.book_id = avg_books.id
            GROUP BY avg_books.id
          ) AS book_totals
        )
      SQL
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
