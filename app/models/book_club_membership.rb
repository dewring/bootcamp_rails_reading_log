class BookClubMembership < ApplicationRecord
  belongs_to :book_club, counter_cache: true
  belongs_to :user

  ROLES = [ "owner", "member" ].freeze

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :book_club_id, message: "is already a member of this club" }
end
