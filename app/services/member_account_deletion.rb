class MemberAccountDeletion
  def initialize(member:)
    @member = member
  end

  def delete_account
    User.transaction do
      # The account is going away: do not enqueue progress jobs for its deleted reading history.
      @member.reading_sessions.delete_all
      ReadingMetric.where(user_id: @member.id).delete_all
      @member.destroy!
    end
  end
end
