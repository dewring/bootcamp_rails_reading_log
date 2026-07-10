class UserChallenge < ApplicationRecord
  enum :status, { active: "active", in_progress: "in_progress", completed: "completed", abandoned: "abandoned", failed: "failed" }

  belongs_to :user
  belongs_to :challenge

  validates :status, presence: true
  validates :challenge_id, uniqueness: { scope: :user_id, message: "User can only enroll in a challenge once" }
end
