require "test_helper"

class Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guests and readers cannot manage member accounts" do
    get admin_members_path
    assert_redirected_to new_user_session_path
    sign_in users(:leika)
    get admin_members_path
    assert_redirected_to root_path
    assert_no_difference("User.count") { post admin_members_path, params: { user: { email: "new@example.com" } } }
    patch admin_member_path(users(:jaina)), params: { user: { nickname: "changed" } }
    assert_equal "esperancita", users(:jaina).reload.nickname
    assert_no_difference("User.count") { delete admin_member_path(users(:jaina)) }
  end

  test "workspace renders real member profiles and fixed navigation" do
    sign_in users(:admin)
    get admin_members_path, params: { member_id: users(:leika).id }
    assert_response :success
    assert_select "h1", text: "Member Management"
    assert_select ".admin-sidebar-nav .is-active[aria-current='page']", text: "Members"
    assert_select ".admin-member-record", count: 3
    assert_select "input#user_email[value='leika@test.com']"
    assert_select "input#admin_member_role[readonly][value='User']"
    assert_select ".admin-member-detail select#user_account_status"
    assert_select "input[value='Save changes']"
    assert_select ".admin-member-record a", text: "Edit", count: 0
  end

  test "search and status filters preserve query and exclude unrelated selection" do
    sign_in users(:admin)
    users(:jaina).update!(account_status: "suspended")
    [ "LEIKA KIM", "MARTITA", "leika@test.com" ].each do |query|
      get admin_members_path, params: { q: query, member_id: users(:jaina).id }
      assert_select ".admin-member-record", count: 1
      assert_select "input#user_nickname[value='martita']"
    end
    get admin_members_path, params: { status: "suspended", q: "jaina", sort: "name" }
    assert_select ".admin-member-record", count: 1
    assert_select "#admin-member-status-menu a[href*='q=jaina'][href*='status=active'][href*='sort=name']"
    get admin_members_path, params: { q: "%" }
    assert_select ".admin-member-record", count: 0
    assert_select ".admin-review-detail-empty"
  end

  test "fifth member enables shared pagination and retains filters" do
    sign_in users(:admin)
    2.times { |index| User.create!(first_name: "Page", last_name: "Reader", nickname: "page#{index}", email: "page#{index}@test.com", password: "password123") }
    get admin_members_path, params: { status: "active", sort: "name" }
    assert_select ".admin-member-record", count: 4
    assert_select ".pagy.series-nav a[href*='page=2'][href*='status=active'][href*='sort=name']"
    get admin_members_path, params: { page: 2, status: "active", sort: "name" }
    assert_select ".admin-member-record", count: 1
  end

  test "admin edits profiles and suspends readers without changing credentials or role" do
    sign_in users(:admin)
    reader = users(:leika)
    password = reader.encrypted_password
    patch admin_member_path(reader), params: { q: "leika", user: { first_name: "Leika", nickname: "updatedreader", account_status: "suspended", role: "admin", password: "injected-password" } }
    assert_redirected_to admin_members_path(member_id: reader.id, q: "leika")
    assert_equal "suspended", reader.reload.account_status
    assert_equal "user", reader.role
    assert_equal password, reader.encrypted_password
    refute reader.active_for_authentication?
    patch admin_member_path(reader), params: { user: { account_status: "active" } }
    assert reader.reload.active_for_authentication?
  end

  test "validation errors retain submitted input and admin accounts are protected" do
    sign_in users(:admin)
    patch admin_member_path(users(:leika)), params: { user: { email: "bad", first_name: "Edited" } }
    assert_response :unprocessable_entity
    assert_select "input#user_first_name[value='Edited']"
    assert_select "[role='alert']", text: /Email/
    assert_equal "leika", users(:leika).reload.first_name
    patch admin_member_path(users(:admin)), params: { user: { account_status: "suspended" } }
    assert_equal "active", users(:admin).reload.account_status
    assert_no_difference("User.count") { delete admin_member_path(users(:admin)) }
  end

  test "admin invites a reader and invalid invitations create no account" do
    sign_in users(:admin)
    assert_difference("User.count", 1) do
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        post admin_members_path, params: { user: { first_name: "New", last_name: "Reader", nickname: "newreader", email: "newreader@test.com", role: "admin" } }
      end
    end
    invited = User.find_by!(nickname: "newreader")
    assert_equal "invited", invited.account_status
    assert_equal "user", invited.role
    assert invited.reset_password_token.present?
    assert_no_difference("User.count") { post admin_members_path, params: { user: { first_name: "New", last_name: "Reader", nickname: "newreader", email: "bad" } } }
    assert_response :unprocessable_entity
    assert_select "input[value='Send invitation']"
  end

  test "admin deletes reader data but cannot delete a club owner" do
    sign_in users(:admin)
    reader = users(:leika)
    club = BookClub.create!(name: "Protected owner")
    membership = club.book_club_memberships.create!(user: reader, role: "owner")
    assert_no_difference("User.count") { delete admin_member_path(reader) }
    membership.destroy!
    assert_difference("User.count", -1) { delete admin_member_path(reader) }
    assert_redirected_to admin_members_path
    assert_empty ReadingSession.where(user_id: reader.id)
    assert_empty UserBook.where(user_id: reader.id)
    assert_empty Review.where(user_id: reader.id)
  end
end
