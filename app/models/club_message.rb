class ClubMessage < ApplicationRecord
  belongs_to :book_club
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1_000 }
end
