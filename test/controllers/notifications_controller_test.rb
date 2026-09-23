require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @book_club = BookClub.create!(name: "Sci-Fi Society")
  end

  test "a guest cannot view notifications" do
    get notifications_path

    assert_redirected_to new_user_session_path
  end

  test "index shows only the signed-in user's notifications" do
    own_notification = create_notification(users(:leika))
    other_notification = create_notification(users(:jaina))

    sign_in users(:leika)
    get notifications_path

    assert_response :success
    assert_select "article#notifications_panel", text: /1 unread/
    assert_select "li##{dom_id(own_notification)}"
    assert_select "li##{dom_id(other_notification)}", count: 0
  end

  test "a user can mark their own notification as read" do
    notification = create_notification(users(:leika))
    sign_in users(:leika)

    patch notification_path(notification), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :no_content
    assert notification.reload.read?
  end

  test "a user cannot mark another user's notification as read" do
    notification = create_notification(users(:leika))
    sign_in users(:jaina)

    patch notification_path(notification)

    assert_redirected_to root_path
    assert_not notification.reload.read?
  end

  private

  def create_notification(recipient)
    BookClubPickNotifier.with(
      record: @book_club,
      book_club_name: @book_club.name,
      book_title: "The Left Hand of Darkness"
    ).deliver(recipient, enqueue_job: false).notifications.first
  end
end
