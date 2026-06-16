class UserBook < ApplicationRecord
  belongs_to :user
  belongs_to :book

  STATUSES = %w[want_to_read reading finished].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :book_id, message: "already has this book in their log" }
end
