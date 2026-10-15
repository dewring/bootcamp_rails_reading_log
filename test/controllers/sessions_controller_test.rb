require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "guest sees the Figma-inspired login page" do
    get new_user_session_path

    assert_response :success
    assert_select "body.auth-page"
    assert_select ".auth-page-shell:not(.auth-page-shell--sign-up)"
    assert_select "h1", text: "Welcome back"
    assert_select "input[name='user[email]'][placeholder='you@example.com']", count: 1
    assert_select "input[name='user[password]'][placeholder='••••••••']", count: 1
    assert_select "input[type='checkbox'][name='user[remember_me]']", count: 1
  end
end
