require "test_helper"
class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "success sing in" do
    sign_in users(:leika)
    get dashboard_path
    assert_response :success
  end
  test "guest is redirected to login" do
    get dashboard_path
    assert_redirected_to new_user_session_path
  end
end
