module ReactionBehavior
  extend ActiveSupport::Concern

  included do
    belongs_to :user
    belongs_to :reaction_type, foreign_key: :kind, primary_key: :key

    validates :kind, presence: true
    validate :selected_kind_is_enabled, if: :selecting_kind?

    scope :eligible, -> { joins(:user).where(users: { account_status: "active" }) }
  end

  private

  def selecting_kind?
    new_record? || will_save_change_to_kind?
  end

  def selected_kind_is_enabled
    return unless reaction_type
    return if reaction_type.enabled?

    errors.add(:kind, "is not enabled")
  end
end
