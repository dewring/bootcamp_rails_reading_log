require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "homepage loads successfully" do
    get root_path
    assert_response :success
  end
end
