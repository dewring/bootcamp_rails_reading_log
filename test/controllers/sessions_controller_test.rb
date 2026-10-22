require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

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

  test "logout broadcasts a disconnect command without reconnection for the signed in user" do
    user = users(:leika)
    sign_in user

    assert_broadcast_on disconnect_stream(user), { type: "disconnect", reconnect: false } do
      delete destroy_user_session_path
    end

    assert_response :redirect
    get book_clubs_path
    assert_redirected_to new_user_session_path
  end

  test "logout ignores a supplied user id and does not disconnect another user" do
    user = users(:leika)
    other_user = users(:jaina)
    sign_in user

    assert_no_broadcasts disconnect_stream(other_user) do
      assert_broadcast_on disconnect_stream(user), { type: "disconnect", reconnect: false } do
        delete destroy_user_session_path, params: { user_id: other_user.id }
      end
    end

    assert_response :redirect
  end

  test "guest logout does not broadcast a user disconnect" do
    assert_no_broadcasts disconnect_stream(users(:leika)) do
      delete destroy_user_session_path
    end

    assert_response :redirect
  end

  private

  def disconnect_stream(user)
    "action_cable/#{user.to_gid_param}"
  end
end
