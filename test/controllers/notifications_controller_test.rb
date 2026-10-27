require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @book_club = BookClub.create!(name: "Sci-Fi Society")
  end

  test "a user can mark their own notification as read" do
    notification = create_notification(users(:leika))
    sign_in users(:leika)

    patch notification_path(notification), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'target="notifications_panel"'
    assert notification.reload.read?
  end

  test "frame refresh returns only the signed in user's latest notifications and unread count without marking them as read" do
    own_notification = create_notification(users(:leika))
    other_notification = create_notification(users(:jaina))
    sign_in users(:leika)

    get notifications_path, headers: { "Turbo-Frame" => "notifications_frame" }

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "turbo-frame#notifications_frame[target='_top']" do
      assert_select "li##{dom_id(own_notification)}", count: 1
      assert_select "li##{dom_id(other_notification)}", count: 0
      assert_select ".notification-count", text: "1"
      assert_select "a[data-turbo-frame='notifications_frame'][data-turbo-prefetch='false'][href='#{notifications_path}'][aria-label='Refresh notifications']"
    end
    assert_not own_notification.reload.read?

    latest_notification = create_notification(users(:leika))
    get notifications_path, headers: { "Turbo-Frame" => "notifications_frame" }

    assert_response :success
    assert_select ".notification-count", text: "2"
    assert_select ".notification-list > li:first-child", id: dom_id(latest_notification)
    assert_not latest_notification.reload.read?
  end

  test "notification frame refresh requires sign in" do
    get notifications_path, headers: { "Turbo-Frame" => "notifications_frame" }

    assert_redirected_to new_user_session_path
    assert_select "turbo-frame", count: 0
  end

  test "a user is redirected home after marking a notification as read with html" do
    notification = create_notification(users(:leika))
    sign_in users(:leika)

    patch notification_path(notification)

    assert_redirected_to root_path
    assert notification.reload.read?
  end

  test "a user cannot mark another user's notification as read" do
    notification = create_notification(users(:leika))
    sign_in users(:jaina)

    patch notification_path(notification)

    assert_redirected_to root_path
    assert_not notification.reload.read?
  end

  test "keeps snapshot text and omits a broken club link after deletion" do
    notification = create_notification(users(:leika))
    @book_club.destroy!
    sign_in users(:leika)

    get root_path

    assert_response :success
    assert_select "li##{dom_id(notification)}", text: /Sci-Fi Society chose The Left Hand of Darkness\./
    assert_select "li##{dom_id(notification)} a", count: 0
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
