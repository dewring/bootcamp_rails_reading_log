class UserBadge < ApplicationRecord
  belongs_to :user
  belongs_to :badge

  validates :awarded_at, presence: true
  validates :badge_id, uniqueness: { scope: :user_id, message: "already awarded to this user" }
end
