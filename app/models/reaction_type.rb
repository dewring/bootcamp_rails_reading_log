class ReactionType < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :label, :emoji, presence: true
  validates :enabled, inclusion: { in: [ true, false ] }
  validate :key_is_unchanged, on: :update, if: :will_save_change_to_key?

  has_many :reactions, foreign_key: :kind, primary_key: :key, dependent: :restrict_with_error
  has_many :review_reactions, foreign_key: :kind, primary_key: :key, dependent: :restrict_with_error
  has_many :club_message_reactions, foreign_key: :kind, primary_key: :key, dependent: :restrict_with_error

  scope :enabled, -> { where(enabled: true) }

  private

  def key_is_unchanged
    errors.add(:key, "cannot be changed after creation")
  end
end
