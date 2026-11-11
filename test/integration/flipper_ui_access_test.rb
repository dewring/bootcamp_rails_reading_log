require "test_helper"

class FlipperUiAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Flipper.add(:discovery_experiment_running_v1)
    Flipper.add(:discovery_hero_trending_v1)
    @running_path = "/flipper/features/discovery_experiment_running_v1"
    @treatment_path = "/flipper/features/discovery_hero_trending_v1"
  end

  test "guests cannot read flags or enable the experiment through the UI" do
    get "/flipper"
    assert_redirected_to "http://www.example.com/users/sign_in"

    post "#{@running_path}/boolean", params: { action: "Enable" }

    assert_redirected_to "http://www.example.com/users/sign_in"
    assert_not Flipper.enabled?(:discovery_experiment_running_v1)
  end

  test "ordinary readers cannot open the UI" do
    sign_in users(:leika)

    get "/flipper"
    assert_response :not_found
  end

  test "ordinary readers cannot read flag settings" do
    sign_in users(:leika)

    get @running_path
    assert_response :not_found
  end

  test "ordinary readers cannot enable the running switch" do
    sign_in users(:leika)

    post "#{@running_path}/boolean", params: { action: "Enable" }
    assert_response :not_found
    assert_not Flipper.enabled?(:discovery_experiment_running_v1)
  end

  test "ordinary readers cannot change the actor percentage" do
    sign_in users(:leika)

    post "#{@treatment_path}/percentage_of_actors", params: { value: "100" }
    assert_response :not_found

    assert_equal 0, Flipper[:discovery_hero_trending_v1].percentage_of_actors_value
  end

  test "admins can read flag settings and enable and disable the running switch with the native form" do
    sign_in users(:admin)

    get "/flipper"
    assert_redirected_to "http://www.example.com/flipper/features"
    follow_redirect!
    assert_response :success
    get @running_path
    assert_response :success
    token = css_select("input[name='authenticity_token']").first["value"]

    post "#{@running_path}/boolean", params: { action: "Enable", authenticity_token: token }

    assert_redirected_to "http://www.example.com#{@running_path}"
    assert Flipper.enabled?(:discovery_experiment_running_v1)

    post "#{@running_path}/boolean", params: { action: "Disable", authenticity_token: token }

    assert_redirected_to "http://www.example.com#{@running_path}"
    assert_not Flipper.enabled?(:discovery_experiment_running_v1)
  end

  test "admins can configure the native actor gate to fifty percent" do
    sign_in users(:admin)
    get @treatment_path
    assert_response :success
    token = css_select("input[name='authenticity_token']").first["value"]

    post "#{@treatment_path}/percentage_of_actors", params: { value: "50", authenticity_token: token }

    assert_redirected_to "http://www.example.com#{@treatment_path}"
    assert_equal 50, Flipper[:discovery_hero_trending_v1].percentage_of_actors_value
  end

  test "even admins cannot change a flag without a valid UI authenticity token" do
    sign_in users(:admin)
    get @running_path

    post "#{@running_path}/boolean", params: { action: "Enable", authenticity_token: "invalid" }

    assert_response :forbidden
    assert_not Flipper.enabled?(:discovery_experiment_running_v1)
  end
end
