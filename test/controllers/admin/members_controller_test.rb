require "test_helper"

class Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @original_invitations_enabled = Rails.configuration.x.member_invitations_enabled
    Rails.configuration.x.member_invitations_enabled = false
  end

  teardown do
    Rails.configuration.x.member_invitations_enabled = @original_invitations_enabled
  end

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
    assert_select ".admin-page-heading a[href*='invite=true']", count: 0
    assert_select ".admin-sidebar-nav .is-active[aria-current='page']", text: "Members"
    assert_select ".admin-member-record", count: 3
    assert_select "input#user_email[value='leika@test.com']"
    assert_select "input#admin_member_role[readonly][value='User']"
    assert_select "input#user_account_status[type='hidden'][value='active']"
    assert_select "button#admin_member_status_trigger[aria-expanded='false'][aria-controls='admin-member-account-status-menu']", text: "Active"
    assert_select "#admin-member-account-status-menu[hidden] [role='option']" do |options|
      assert_equal [ "Active", "Suspended" ], options.map(&:text)
    end
    assert_select "input[value='Save changes']"
    assert_select "#admin-member-status-menu a" do |options|
      assert_equal [ "All statuses", "Active", "Suspended" ], options.map(&:text)
    end
    assert_select ".admin-member-record a", text: "Edit", count: 0
  end

  test "admin opens the invitation form through the workspace link without creating an account" do
    Rails.configuration.x.member_invitations_enabled = true
    sign_in users(:admin)
    get admin_members_path, params: { q: "leika", status: "active", sort: "name", page: 1 }
    invitation_url = nil
    assert_select ".admin-page-heading a[href*='invite=true'][href*='q=leika'][href*='status=active'][href*='sort=name'][href*='page=1']", text: /Invite Member/, count: 1 do |links|
      invitation_url = links.first["href"]
    end

    assert_no_difference [ "User.count", "ActionMailer::Base.deliveries.size" ] do
      get invitation_url
    end

    assert_response :success
    assert_select "h2#admin-member-detail-title", text: "Invite a member"
    assert_select ".admin-member-form[action='#{admin_members_path}'] input[value='Send invitation']"
    assert_select ".admin-member-form input[name='_method']", count: 0
    assert_select ".admin-member-form input[name='q'][value='leika']"
    assert_select ".admin-member-form input[name='status'][value='active']"
    assert_select ".admin-member-form input[name='sort'][value='name']"
    assert_select ".admin-member-record", count: 1
  end

  test "disabled invitations cannot be opened or submitted through direct requests" do
    sign_in users(:admin)
    get admin_members_path, params: { invite: true, member_id: users(:leika).id, status: "invited" }

    assert_response :success
    assert_select "h2#admin-member-detail-title", text: "Member profile"
    assert_select "input[value='Send invitation']", count: 0
    assert_select "input[value='Save changes']", count: 1
    assert_select "#admin-member-status-menu a[href*='status=invited']", count: 0
    assert_nil assigns(:status)

    assert_no_difference [ "User.count", "ActionMailer::Base.deliveries.size" ] do
      post admin_members_path, params: { user: { first_name: "Hidden", last_name: "Invite", nickname: "hiddeninvite", email: "hiddeninvite@test.com" } }
    end
    assert_redirected_to root_path
  end

  test "invited status filter is reachable and preserves search and sorting" do
    Rails.configuration.x.member_invitations_enabled = true
    users(:leika).update!(account_status: "invited")
    users(:jaina).update!(account_status: "suspended")
    sign_in users(:admin)
    get admin_members_path, params: { q: "leika", sort: "name" }
    invited_url = nil
    assert_select "#admin-member-status-menu a[href*='status=invited'][href*='q=leika'][href*='sort=name']", text: "Invited", count: 1 do |links|
      invited_url = links.first["href"]
    end

    get invited_url

    assert_response :success
    assert_equal [ users(:leika).id ], assigns(:members).map(&:id)
    assert_select ".admin-member-record", count: 1
    assert_select ".admin-member-status--invited", text: "Invited"
    assert_select "button[aria-controls='admin-member-status-menu']", text: "Invited"
    assert_select "#admin-member-status-menu a.is-selected[aria-current='true']", text: "Invited", count: 1
    assert_select "input[name='q'][value='leika']"
    assert_select "#admin-member-sort-menu a.is-selected", text: "Member name"
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

  test "admins cannot change their own or another admin's email through member management" do
    users(:jaina).update!(role: "admin")
    sign_in users(:admin)

    [ users(:admin), users(:jaina) ].each do |member|
      get admin_members_path, params: { member_id: member.id }
      assert_response :success
      assert_select "input#user_email[readonly][value='#{member.email}']"

      protected_attributes = -> { member.reload.attributes.slice("email", "first_name", "encrypted_password", "reset_password_token") }
      assert_no_changes protected_attributes do
        patch admin_member_path(member), params: { user: { email: "blocked#{member.id}@test.com", first_name: "Blocked Edit" } }
      end
      assert_redirected_to root_path
    end
  end

  test "protected email submitted unchanged still permits admin profile edits" do
    users(:jaina).update!(role: "admin")
    sign_in users(:admin)

    [ users(:admin), users(:jaina) ].each do |member|
      original_email = member.email
      patch admin_member_path(member), params: { user: { email: original_email, first_name: "Edited Profile" } }

      assert_redirected_to admin_members_path(member_id: member.id)
      assert_equal "Edited Profile", member.reload.first_name
      assert_equal original_email, member.email
    end
  end

  test "admin may change a regular reader's email without changing their password" do
    sign_in users(:admin)
    reader = users(:leika)
    password = reader.encrypted_password
    get admin_members_path, params: { member_id: reader.id }
    assert_select "input#user_email[readonly]", count: 0

    patch admin_member_path(reader), params: { user: { email: "updatedreader@test.com" } }

    assert_redirected_to admin_members_path(member_id: reader.id)
    assert_equal "updatedreader@test.com", reader.reload.email
    assert_equal password, reader.encrypted_password
  end

  test "admin invites a reader and invalid invitations create no account" do
    Rails.configuration.x.member_invitations_enabled = true
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
