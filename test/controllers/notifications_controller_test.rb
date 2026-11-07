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

  test "leader notifications open the leaderboard and retain text after club deletion" do
    user = users(:leika)
    event = BookClubLeaderNotifier.with(
      record: @book_club, book_club_name: @book_club.name, book_title: "A Book", leader_names: [ "Mina" ]
    ).deliver(user, enqueue_job: false)
    notification = event.notifications.first
    sign_in user

    get notifications_path

    assert_response :success
    assert_select "li##{dom_id(notification)} a[href='#{book_club_leaderboard_path(@book_club)}']",
      text: "Mina is now first in Sci-Fi Society for A Book."
    assert_not notification.reload.read?

    @book_club.destroy!
    get notifications_path

    assert_response :success
    assert_select "li##{dom_id(notification)}", text: /Mina is now first in Sci-Fi Society for A Book\./
    assert_select "li##{dom_id(notification)} a", count: 0
  end

  test "a returning post author sees the saved reply notification with a discussion link" do
    recipient = users(:leika)
    author = users(:jaina)
    @book_club.book_club_memberships.create!(user: recipient, role: "owner")
    @book_club.book_club_memberships.create!(user: author, role: "member")
    post = @book_club.club_messages.create!(user: recipient, body: "A discussion question")
    post.replies.create!(book_club: @book_club, user: author, body: "An answer")
    notification = BookClubReplyNotifier.last.notifications.first
    sign_in recipient

    get notifications_path

    assert_response :success
    assert_select "li##{dom_id(notification)} a[href='#{book_club_club_messages_path(@book_club)}']",
      text: "#{author.nickname} replied to your discussion in Sci-Fi Society."
    assert_not notification.reload.read?

    @book_club.destroy!
    get notifications_path

    assert_response :success
    assert_select "li##{dom_id(notification)}", text: /#{Regexp.escape(author.nickname)} replied to your discussion in Sci-Fi Society\./
    assert_select "li##{dom_id(notification)} a", count: 0
  end

  test "a returning member sees saved name and deadline notifications even after the club is deleted" do
    user = users(:leika)
    @book_club.book_club_memberships.create!(user: user, role: "owner")
    @book_club.update!(name: "New circle", reading_deadline: Date.new(2026, 12, 15))
    sign_in user

    get notifications_path

    assert_response :success
    assert_select ".notification-content", text: /Sci-Fi Society was renamed to New circle\./
    assert_select ".notification-content", text: /New circle set the reading deadline to December 15, 2026\./
    assert_select ".notification-count", text: "2"
    assert_select ".notification-content a[href='#{book_club_path(@book_club)}']", count: 2
    assert_equal 2, user.notifications.unread.count

    @book_club.destroy!
    get notifications_path

    assert_response :success
    assert_select ".notification-content", text: /Sci-Fi Society was renamed to New circle\./
    assert_select ".notification-content", text: /New circle set the reading deadline to December 15, 2026\./
    assert_select ".notification-content a", count: 0
    assert_equal 2, user.notifications.unread.count
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
