class DiscoveryExposure < ApplicationRecord
  EXPERIMENT_KEY = "discovery_v1".freeze

  validates :experiment_key, presence: true, uniqueness: { scope: :user_id }
  validates :variant, inclusion: { in: [ "control", "treatment" ] }
  validates :shown_book_ids, :exposed_at, presence: true
  validate :conversion_is_within_exposure_window

  belongs_to :user

  private

  def conversion_is_within_exposure_window
    return if converted_at.nil? || exposed_at.nil?
    return if converted_at >= exposed_at && converted_at < exposed_at + 24.hours

    errors.add(:converted_at, "must be within 24 hours after exposure")
  end
end
