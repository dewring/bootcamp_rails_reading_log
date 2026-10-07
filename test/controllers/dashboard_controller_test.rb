require "test_helper"
class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "success sing in" do
    sign_in users(:leika)
    get dashboard_path
    assert_response :success
    assert_select ".my-log-page"
    assert_select ".my-log-sidebar"
    assert_select ".my-log-navigation-item--active", text: /My Log/
    assert_select ".my-log-intro h1", text: "Hello, martita"
    assert_select ".my-log-section--reading h2", text: "Reading"
    assert_select ".my-log-section--want-to-read h2", text: "Want to Read"
    assert_select ".my-log-carousel", count: 2
    assert_select ".my-log-position", count: 0
  end

  test "my log intro keeps the in-progress summary while pagination text is hidden" do
    sign_in users(:leika)

    get dashboard_path

    assert_select ".my-log-season-note strong", text: /\d+ books? in progress\z/
    assert_select ".my-log-position", count: 0
  end
  test "guest is redirected to login" do
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "books with reading sessions appear in Reading even when their saved status is want to read" do
    sign_in users(:leika)
    book = books(:pragmatic)
    ReadingSession.create!(user: users(:leika), book: book, read_on: Date.today, pages_read: 10)

    get dashboard_path

    assert_select ".my-log-section--reading a[href='#{book_reading_journal_path(book)}']", count: 1
    assert_select ".my-log-section--want-to-read a[href='#{book_path(book)}']", count: 0
  end

  test "empty shelves show concise messages without catalog links" do
    sign_in users(:jaina)

    get dashboard_path

    assert_response :success
    assert_select ".my-log-section--reading .my-log-empty-shelf", text: "No books in progress yet."
    assert_select ".my-log-section--reading .my-log-empty-shelf a", count: 0
    assert_select ".my-log-section--want-to-read .my-log-empty-shelf", text: "No books saved for later yet."
    assert_select ".my-log-section--want-to-read .my-log-empty-shelf a", count: 0
  end
end
