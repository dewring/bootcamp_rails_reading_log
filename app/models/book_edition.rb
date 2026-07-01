class BookEdition < ApplicationRecord
  belongs_to :book
  has_one_attached :cover_image

  validates :ol_edition_key, presence: true

  after_commit :delete_cache

  private

  def delete_cache
    Rails.cache.delete("book:#{book_id}:editions:list")
  end
end
