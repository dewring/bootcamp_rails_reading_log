module ReactionBehavior
  extend ActiveSupport::Concern

  included do
    class_attribute :reaction_target_name, instance_writer: false

    belongs_to :user
    belongs_to :reaction_type, foreign_key: :kind, primary_key: :key

    validates :kind, presence: true
    validate :selected_kind_is_enabled, if: :selecting_kind?

    scope :eligible, -> { joins(:user).where(users: { account_status: "active" }) }

    after_commit :refresh_reaction_totals, if: -> { destroyed? || saved_change_to_kind? }
  end

  private

  def refresh_reaction_totals
    target = self.class.reflect_on_association(reaction_target_name)
    ReactionTotalsJob.perform_later(target.class_name, self[target.foreign_key])
  end

  def selecting_kind?
    new_record? || will_save_change_to_kind?
  end

  def selected_kind_is_enabled
    return unless reaction_type
    return if reaction_type.enabled?

    errors.add(:kind, "is not enabled")
  end
end
