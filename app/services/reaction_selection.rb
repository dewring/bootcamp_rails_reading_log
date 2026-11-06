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
  rescue ActiveRecord::RecordNotUnique
    # A concurrent first selection won the unique reader/target pair.
    raise unless @target.reactions.exists?(user_id: @user.id)

    retry
  rescue ActiveRecord::RecordInvalid => error
    # The same collision can be caught by model validation before INSERT.
    raise unless error.record.errors.of_kind?(:user_id, :taken)

    retry
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
    # Keep target deletion outside the write, without serializing the reader's
    # other reactions. A savepoint lets creation collisions roll back safely.
    @target.with_lock("FOR SHARE", requires_new: true) do
      @user.reload
      reaction = @target.reactions.lock.find_or_initialize_by(user: @user)
      yield reaction
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
