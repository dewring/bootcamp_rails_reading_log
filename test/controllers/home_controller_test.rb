require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "homepage loads successfully" do
    get root_path

    assert_response :success
    assert_select "button.nav-account-trigger[aria-label='Account'][aria-expanded='false'] svg.account-icon"
    assert_select "ul#account_dropdown[hidden] li a", count: 2
    assert_select "ul#account_dropdown li a[href='#{new_user_session_path}']", text: "Sign in"
    assert_select "ul#account_dropdown li a[href='#{new_user_registration_path}']", text: "Sign up"
  end

  test "signed-in homepage renders the notification sidebar" do
    sign_in users(:leika)

    get root_path

    assert_response :success
    assert_select "li#notifications_panel"
    assert_select "button.notification-trigger[aria-expanded='false']"
    assert_select "button.nav-account-trigger[aria-label='Account'][aria-expanded='false'] svg.account-icon"
    assert_select "ul#account_dropdown[hidden] li a", count: 1
    assert_select "ul#account_dropdown li a[href='#{destroy_user_session_path}']", text: "Sign out"
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

  test "home page renders resized cover variant when attached" do
    book = Book.create!(title: "Cover Test Book", author: "Author", total_pages: 100)
    book.cover_image.attach(fixture_file_upload("cover_test.jpg", "image/jpeg"))

    get root_path

    assert_response :success
    assert_select "img.book-cover"
  end
end
