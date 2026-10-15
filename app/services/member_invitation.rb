class MemberInvitation
  def initialize(member:)
    @member = member
  end

  def invite_member
    @member.assign_attributes(role: "user", account_status: "invited", password: SecureRandom.hex(32))
    @member.save!
    @member.send_reset_password_instructions
    @member
  end
end
