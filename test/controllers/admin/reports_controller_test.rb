require "test_helper"

class Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guests are redirected to sign in instead of seeing the report" do
    get admin_report_path
    assert_redirected_to new_user_session_path
  end

  test "signed-in regular readers are redirected home instead of seeing the report" do
    sign_in users(:leika)
    get admin_report_path
    assert_redirected_to root_path
  end

  test "admins see the report page with Reports listed first and marked active in the sidebar" do
    sign_in users(:admin)
    get admin_report_path

    assert_response :success
    assert_select "h1", text: "Reading Activity Report"
    assert_select ".admin-sidebar-nav a:first-child", text: "Reports"
    assert_select ".admin-sidebar-nav .is-active[aria-current='page']", text: "Reports"
  end
end
