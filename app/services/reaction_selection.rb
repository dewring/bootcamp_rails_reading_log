class ReactionSelection
  def initialize(user:, target:)
    @user = user
    @target = target
  end

  def select_kind(kind:)
    with_locked_reaction do |reaction|
      Pundit.authorize(@user, reaction, reaction.persisted? ? :update? : :create?)
      save_selected_kind(reaction, kind)
    end
  end

  def clear_selection
    with_locked_reaction do |reaction|
      Pundit.authorize(@user, reaction, :destroy?)
      reaction.destroy! if reaction.persisted?
      reaction
    end
  end

  private

  def with_locked_reaction
    # Use the same lock order for every target. Reloading the user also makes
    # account eligibility changes take effect before authorizing a write.
    @user.with_lock do
      @target.with_lock("FOR SHARE") do
        reaction = @target.reactions.find_or_initialize_by(user: @user)
        yield reaction
      end
    end
  end

  def save_selected_kind(reaction, kind)
    return reaction if reaction.persisted? && reaction.kind == kind

    reaction.kind = kind
    # Hold the catalog row while validating/saving so a concurrent disable
    # cannot turn a new selection into a disabled choice before commit.
    type = ReactionType.lock("FOR SHARE").find_by(key: reaction.kind)
    reaction.reaction_type = type if type
    reaction.save!
    reaction
  end
end
