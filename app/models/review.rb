class Review < ApplicationRecord
  belongs_to :user
  belongs_to :book

  validates :rating, inclusion: { in: 0..5 }
  validates :user_id, uniqueness: { scope: :book_id }
end
