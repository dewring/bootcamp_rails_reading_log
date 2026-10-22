class BookClubMembership < ApplicationRecord
  belongs_to :book_club, counter_cache: true
  belongs_to :user

  ROLES = [ "owner", "member" ].freeze

  after_commit :refresh_book_club_leaderboard, on: [ :create, :update, :destroy ]
  after_destroy_commit :broadcast_discussion_access_check

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :book_club_id, message: "is already a member of this club" }

  private

  def broadcast_discussion_access_check
    ClubDiscussionChannel.broadcast_to(book_club, { type: "access.recheck" })
  end

  def refresh_book_club_leaderboard
    BookClubLeaderboardJob.perform_later(book_club_id)
  end
end
