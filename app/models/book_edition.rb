class BookEdition < ApplicationRecord
  belongs_to :book
  has_one_attached :cover_image

  validates :ol_edition_key, presence: true
end
