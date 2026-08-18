class Challenge < ApplicationRecord
  enum :goal_type, { pages_per_day: "pages_per_day", books_total: "books_total", streak_days: "streak_days" }

  has_many :user_challenges, dependent: :destroy
  has_many :users, through: :user_challenges

  validates :title, presence: true
  validates :goal_type, presence: true
  validates :goal_value, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :starts_at, presence: true
  validates :ends_at, presence: true, comparison: { greater_than: :starts_at }

  # What the user needs to do, without the date window — kept separate from
  # #date_range so views can put each on its own line for readability.
  def goal_summary
    case goal_type
    when "streak_days"
      "Read #{goal_value} days in a row"
    when "pages_per_day"
      "Read #{goal_value} pages per day"
    when "books_total"
      "Finish #{goal_value} books"
    end
  end

  # The challenge window that #goal_summary applies to, shown on its own line.
  def date_range
    "#{starts_at.strftime('%b %d, %Y')} – #{ends_at.strftime('%b %d, %Y')}"
  end
end
