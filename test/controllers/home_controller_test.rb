require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "homepage loads successfully" do
    get root_path

    assert_response :success
    assert_select "section.home-hero[aria-labelledby='home-hero-title']"
    assert_select "h1#home-hero-title", "Summer Reading Challenge — Join Now"
    assert_select "section.home-section", count: 2
    assert_select "h2", text: "Most Read"
    assert_select "h2", text: "New Books"
    assert_select "a.home-view-all[href='#{books_path(filter: 'most_read')}']", count: 1
    assert_select "a.home-view-all[href='#{books_path(filter: 'new_books')}']", count: 1
    assert_select "footer.home-footer"
    assert_select "button.nav-account-trigger[aria-label='Account'][aria-expanded='false'] img.account-icon"
    assert_select "button.nav-menu-trigger[aria-label='Menu'][aria-expanded='false'] img.nav-action-icon"
    assert_select "li.nav-menu[data-action*='mouseenter->nav-menu#enter'][data-action*='mouseleave->nav-menu#leave']"
    assert_select "li.account-menu[data-action*='mouseenter->account-dropdown#enter'][data-action*='mouseleave->account-dropdown#leave']"
    assert_select "ul#nav_menu_dropdown[hidden] li a[href='#{books_path}']", text: "Catalog"
    assert_select "ul#account_dropdown[hidden] li a", count: 2
    assert_select "ul#account_dropdown li a[href='#{new_user_session_path}']", text: "Log In"
    assert_select "ul#account_dropdown li a[href='#{new_user_registration_path}']", text: "Sign Up"
  end

  test "signed-in homepage renders the notification sidebar" do
    sign_in users(:leika)

    get root_path

    assert_response :success
    assert_select "li#notifications_panel"
    assert_select "li#notifications_panel[data-action*='mouseenter->notification-dropdown#enter'][data-action*='mouseleave->notification-dropdown#leave']"
    assert_select "button.notification-trigger[aria-expanded='false']"
    assert_select "button.nav-account-trigger[aria-label='Account'][aria-expanded='false'] img.account-icon"
    assert_select "ul#account_dropdown[hidden] li a", count: 5
    assert_select "ul#account_dropdown li a[href='#{dashboard_path}']", text: "My Log"
    assert_select "ul#account_dropdown li a[href='#{reviews_path}']", text: "Reviews"
    assert_select "ul#account_dropdown li a[href='#{reading_sessions_path}']", text: "History"
    assert_select "ul#account_dropdown li a[href='#{edit_user_registration_path}']", text: "Settings"
    assert_select "ul#account_dropdown li a[href='#{destroy_user_session_path}']", text: "Log Out"
  end

  test "admin account menu includes the management workspace" do
    sign_in users(:admin)

    get root_path

    assert_response :success
    assert_select "ul#account_dropdown li a[href='#{admin_root_path}']", text: "Manage", count: 1
    assert_select "li.account-dropdown-divider", count: 1
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
