class Genre < ApplicationRecord
  GENRES = %w[
  Fiction
  Non-Fiction
  Mystery
  Thriller
  Romance
  Fantasy
  Science-Fiction
  Biography
  History
  Self-Help
  Horror
  Poetry
  ].freeze

  validates :name, presence: true, inclusion: { in: GENRES }

  has_many :book_genres, dependent: :destroy
  has_many :books, through: :book_genres
end
