class BookGenre < ApplicationRecord
  belongs_to :book
  belongs_to :genre

  validates :book_id, uniqueness: { scope: :genre_id }
end
