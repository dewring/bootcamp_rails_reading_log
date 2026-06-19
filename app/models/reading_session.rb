class ReadingSession < ApplicationRecord
  belongs_to :user
  belongs_to :book

  validates :read_on, presence: true
  validates :pages_read, presence: true, numericality: { greater_than: 0 }
end
