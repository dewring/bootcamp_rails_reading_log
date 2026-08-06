class Badge < ApplicationRecord
  enum :badge_type, {
    first_session: "first_session",
    week_streak: "week_streak",
    bookworm: "bookworm",
    challenge_complete: "challenge_complete",
    page_turner: "page_turner"
  }

  has_many :user_badges, dependent: :destroy
  has_many :users, through: :user_badges

  validates :badge_type, presence: true, uniqueness: true
  validates :name, presence: true, uniqueness: true
  validates :description, presence: true

  COLORS = {
    "first_session"      => "#8bc34a",
    "week_streak"        => "#f59e0b",
    "bookworm"           => "#8b5cf6",
    "challenge_complete" => "#10b981",
    "page_turner"        => "#ec4899"
  }.freeze

  def color
    COLORS.fetch(badge_type, "#2f9e44")
  end
end
