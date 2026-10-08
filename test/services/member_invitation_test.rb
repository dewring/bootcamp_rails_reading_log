require "test_helper"

class MemberInvitationTest < ActiveSupport::TestCase
  test "invitation creates an ordinary invited account with a password setup token" do
    member = User.new(first_name: "New", last_name: "Reader", nickname: "invite_service", email: "invite_service@test.com")
    MemberInvitation.new(member: member).invite_member
    assert member.persisted?
    assert_equal "user", member.role
    assert_equal "invited", member.account_status
    assert member.reset_password_token.present?
    member.reset_password!("newpassword123", "newpassword123")
    assert_equal "active", member.reload.account_status
    assert member.valid_password?("newpassword123")
  end

  test "suspension remains in force after password recovery" do
    member = users(:leika)
    member.update!(account_status: "suspended")
    member.reset_password!("newpassword123", "newpassword123")
    refute member.active_for_authentication?
    assert_equal :suspended, member.inactive_message
  end
end
