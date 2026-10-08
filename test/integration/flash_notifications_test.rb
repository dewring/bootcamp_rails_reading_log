require "test_helper"

class FlashNotificationsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "club changes use a single dismissible success notification" do
    sign_in users(:leika)
    post book_clubs_path, params: { book_club: { name: "Toast club", description: "Read together" } }
    follow_redirect!
    assert_notification "Book club created."

    club = BookClub.find_by!(name: "Toast club")
    patch book_club_path(club), params: { book_club: { name: "Renamed club" } }
    follow_redirect!
    assert_notification "Book club updated."

    delete book_club_path(club)
    follow_redirect!
    assert_notification "Book club deleted."
    get book_clubs_path
    assert_select ".flash-notifications", count: 0
  end

  test "admin changes use the same notification without duplicate flashes" do
    sign_in users(:admin)
    patch admin_book_path(books(:pragmatic)), params: { book: { title: "Updated book" } }
    follow_redirect!
    assert_notification "Book updated."
    assert_select "body.admin-layout > .flash-notifications", count: 1
  end

  test "signup and account updates show concise success messages" do
    post user_registration_path, params: { user: { first_name: "Toast", last_name: "Reader", nickname: "toastreader", email: "toast@example.com", password: "password123", password_confirmation: "password123" } }
    follow_redirect!
    assert_notification "Welcome! Your account is ready."

    patch user_registration_path, params: { user: { nickname: "newtoastreader" } }
    follow_redirect!
    assert_notification "Account changes saved."
  end

  test "authorization alerts use an accessible dismissible error notification" do
    sign_in users(:leika)
    get admin_catalog_path
    follow_redirect!
    assert_select ".flash-notification--alert[role='alert']", count: 1
    assert_select ".flash-notification--alert button[aria-label='Dismiss notification']"
    assert_select ".flash-notification--alert .flash-notification-icon", count: 0
    assert_select ".flash-notification--alert p", text: /not authorized/i
  end

  private

  def assert_notification(message)
    assert_response :success
    assert_select ".flash-notifications", count: 1
    assert_select ".flash-notification--notice[role='status'][aria-atomic='true']", count: 1
    assert_select ".flash-notification-message p", text: message
    assert_select "img.flash-notification-icon[width='12'][height='12']", count: 1
    assert_select "button[aria-label='Dismiss notification'][data-action='flash-notifications#dismiss']", count: 1
  end
end
