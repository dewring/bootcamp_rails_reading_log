class ClubMessageReactionPolicy < ReactionPolicy
  def show?
    super && !record.club_message.deleted?
  end

  private

  def reaction_target
    record.club_message
  end
end
