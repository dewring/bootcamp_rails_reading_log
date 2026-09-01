require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    @user = users(:leika)
  end

  test "throttles sign-in attempts after 5 requests in 20 seconds" do
    travel_to Time.current do
      5.times do
        post user_session_path, params: { user: { email: @user.email, password: "wrong" } }
        assert_response :unprocessable_entity
      end

      post user_session_path, params: { user: { email: @user.email, password: "wrong" } }
      assert_response 429
    end
  end
end
