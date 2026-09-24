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

    assert_response :no_content
    assert notification.reload.read?
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
