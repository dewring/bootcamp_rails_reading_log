require "test_helper"

class PersonalNavigationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "members and admins see only library links in library sidebars and only Settings in settings" do
    [ users(:leika), users(:admin) ].each do |user|
      sign_in user
      [ [ dashboard_path, "My Log" ], [ reviews_path, "Reviews" ], [ reading_sessions_path, "History" ] ].each do |path, label|
        get path

        assert_response :success
        assert_select ".my-log-sidebar .my-log-profile", count: 1
        assert_select ".my-log-sidebar nav a" do |links|
          assert_equal [ "My Log", "Reviews", "History" ], links.map { |link| link.text.strip }
        end
        assert_select ".my-log-sidebar nav [aria-current='page']", text: label, count: 1
        assert_select ".my-log-sidebar a[href='#{edit_user_registration_path}']", count: 0
        assert_select "#account_dropdown a[href='#{edit_user_registration_path}']", text: "Settings"
      end

      get edit_user_registration_path

      assert_response :success
      assert_select ".my-log-sidebar[aria-label='Settings navigation'] .my-log-profile", count: 1
      assert_select ".my-log-sidebar nav[aria-label='Settings'] a", count: 1, text: "Settings"
      assert_select ".my-log-sidebar nav a[aria-current='page'][href='#{edit_user_registration_path}']", count: 1
      assert_select ".settings-profile-card", count: 1
      assert_select ".settings-account-card form.settings-form", count: 1
      sign_out user
    end
  end
end
