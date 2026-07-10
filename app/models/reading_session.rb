class ReadingSession < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :book_edition, optional: true

  validates :read_on, presence: true
  validates :pages_read, presence: true, numericality: { greater_than: 0 }

  after_commit :recalculate_progress
  after_commit :recalculate_challenge_progress

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
  def recalculate_challenge_progress
    ChallengeProgressJob.perform_later(user)
  end
end
