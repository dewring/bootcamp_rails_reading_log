require "test_helper"

class BookClubPickNotifierTest < ActiveSupport::TestCase
  setup do
    @user = users(:leika)
    @book_club = BookClub.create!(name: "Sci-Fi Society")
  end

  test "persists snapshot params for each recipient" do
    event = BookClubPickNotifier.with(
      record: @book_club,
      book_club_name: @book_club.name,
      book_title: "The Left Hand of Darkness"
    ).deliver(@user, enqueue_job: false)

    notification = event.notifications.first

    assert_equal @user, notification.recipient
    assert_equal "Sci-Fi Society", event.params[:book_club_name]
    assert_equal "The Left Hand of Darkness", event.params[:book_title]
    assert_equal "Sci-Fi Society chose The Left Hand of Darkness.", notification.message
  end

  test "broadcasts a refreshed panel through Noticed's Action Cable method" do
    event = BookClubPickNotifier.with(
      record: @book_club,
      book_club_name: @book_club.name,
      book_title: "The Left Hand of Darkness"
    ).deliver(@user, enqueue_job: false)
    notification = event.notifications.first
    broadcasts = []

    Noticed::NotificationChannel.stub(:broadcast_to, ->(*args) { broadcasts << args }) do
      Noticed::DeliveryMethods::ActionCable.new.perform(:action_cable, notification)
    end

    stream, message = broadcasts.first

    assert_equal @user, stream
    assert_includes message, 'action="replace"'
    assert_includes message, 'target="notifications_panel"'
    assert_includes message, "Sci-Fi Society chose The Left Hand of Darkness."
    assert_includes message, "1 unread"
  end

  test "delivery retries do not create another event or notification" do
    event = BookClubPickNotifier.with(
      record: @book_club,
      book_club_name: @book_club.name,
      book_title: "The Left Hand of Darkness"
    ).deliver(@user, enqueue_job: false)
    notification = event.notifications.first
    event_count = Noticed::Event.count
    notification_count = Noticed::Notification.count

    Noticed::NotificationChannel.stub(:broadcast_to, ->(*) { }) do
      2.times { Noticed::DeliveryMethods::ActionCable.new.perform(:action_cable, notification) }
    end

    assert_equal event_count, Noticed::Event.count
    assert_equal notification_count, Noticed::Notification.count
  end
end
