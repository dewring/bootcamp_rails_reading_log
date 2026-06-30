class ReadingSession < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :book_edition, optional: true

  validates :read_on, presence: true
  validates :pages_read, presence: true, numericality: { greater_than: 0 }
end
