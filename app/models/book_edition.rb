class BookEdition < ApplicationRecord
  include Displayable
  include CatalogEntry
  include HasAttachedCoverImage

  belongs_to :book

  validates :ol_edition_key, presence: true

  after_commit :delete_cache

  private

  def delete_cache
    Rails.cache.delete("book:#{book_id}:editions:list")
  end
end
