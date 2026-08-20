class BookClub < ApplicationRecord
  has_many :book_club_memberships, dependent: :destroy
  has_many :users, through: :book_club_memberships

  validates :name, presence: true
end
