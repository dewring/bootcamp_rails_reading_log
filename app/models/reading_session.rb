class ReadingSession < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :book_edition, optional: true

  validates :read_on, presence: true
  validates :pages_read, presence: true, numericality: { greater_than: 0 }

  after_commit :refresh_book_club_leaderboards, on: [ :create, :update, :destroy ]
  after_commit :recalculate_progress
  after_commit :award_badges
  include RecalculateChallengeProgress

  def self.current_streak(user)
    session_dates = where(user: user, read_on: 90.days.ago.to_date..Date.current)
                                   .distinct.pluck(:read_on).to_set
    streak = 0
    date = Date.current
    while session_dates.include?(date)
      streak += 1
      date -= 1.day
    end
    streak
  end

  private

  def recalculate_progress
    BookProgressJob.perform_later(user, book)
  end

  def award_badges
    BadgeAwardJob.perform_later(user)
  end

  def refresh_book_club_leaderboards
    BookClub
      .where(current_book_id: affected_book_ids)
      .pluck(:id)
      .each { |book_club_id| BookClubLeaderboardJob.perform_later(book_club_id) }
  end

  def affected_book_ids
    [ book_id, previous_changes.dig("book_id", 0) ].compact.uniq
  end
end
