class Challenge < ApplicationRecord
  enum :goal_type, { pages_per_day: "pages_per_day", books_total: "books_total", streak_days: "streak_days" }

  has_many :user_challenges, dependent: :destroy
  has_many :users, through: :user_challenges

  validates :title, presence: true
  validates :goal_type, presence: true
  validates :goal_value, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :starts_at, presence: true
  validates :ends_at, presence: true, comparison: { greater_than: :starts_at }
end
