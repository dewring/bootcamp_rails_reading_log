require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "homepage loads successfully" do
    get root_path
    assert_response :success
  end

  test "reset button appears when a genre filter is active" do
    get root_path, params: { genre: "Fiction" }
    assert_response :success
    assert_select "a.genre-pill[href='#{root_path}']", text: "Reset"
  end

  test "reset button is hidden when no genre filter is active" do
    get root_path
    assert_response :success
    assert_select "a.genre-pill-reset", false
  end

  test "most read shows empty state when no books match selected genre" do
    get root_path, params: { genre: "Poetry" }
    assert_response :success
    assert_select "p.empty-state", "No books found for this genre."
  end
end
