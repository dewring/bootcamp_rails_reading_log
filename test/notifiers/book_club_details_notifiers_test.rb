require "test_helper"

class BookClubDetailsNotifiersTest < ActiveSupport::TestCase
  setup do
    @user = users(:leika)
    @book_club = BookClub.create!(name: "Current circle")
  end

  test "rename notifications retain both names after the club is changed and deleted" do
    event = BookClubRenameNotifier.with(
      record: @book_club, previous_name: "Old circle", book_club_name: "New circle"
    ).deliver(@user, enqueue_job: false)

    @book_club.update!(name: "Later circle")
    @book_club.destroy!

    notification = event.notifications.first.reload
    assert_equal "Old circle was renamed to New circle.", notification.message
    assert notification.unread?
    assert_nil notification.record
  end

  test "deadline notifications retain the saved deadline after the club is changed and deleted" do
    event = BookClubDeadlineNotifier.with(
      record: @book_club, book_club_name: "Deadline circle", reading_deadline: "2026-12-15"
    ).deliver(@user, enqueue_job: false)

    @book_club.update!(name: "Later circle", reading_deadline: Date.new(2027, 1, 1))
    @book_club.destroy!

    notification = event.notifications.first.reload
    assert_equal "Deadline circle set the reading deadline to December 15, 2026.", notification.message
    assert notification.unread?
    assert_nil notification.record
  end

  test "removing a deadline has an explicit notification message" do
    event = BookClubDeadlineNotifier.with(
      record: @book_club, book_club_name: "Deadline circle", reading_deadline: nil
    ).deliver(@user, enqueue_job: false)

    assert_equal "Deadline circle cleared its reading deadline.", event.notifications.first.message
  end

  test "rename and deadline delivery retries broadcast the panel without duplicating rows or resetting read state" do
    events = [
      BookClubRenameNotifier.with(record: @book_club, previous_name: "Old circle", book_club_name: "New circle"),
      BookClubDeadlineNotifier.with(record: @book_club, book_club_name: "New circle", reading_deadline: "2026-12-15")
    ].map { |event| event.deliver(@user, enqueue_job: false) }

    events.each do |event|
      notification = event.notifications.first
      broadcasts = []
      notification.mark_as_read!
      read_at = notification.read_at

      assert_no_difference [ "Noticed::Event.count", "Noticed::Notification.count" ] do
        Noticed::NotificationChannel.stub(:broadcast_to, ->(*args) { broadcasts.push(args) }) do
          2.times { Noticed::DeliveryMethods::ActionCable.new.perform(:action_cable, notification) }
        end
      end

      assert_equal 2, broadcasts.size
      broadcasts.each do |recipient, html|
        assert_equal @user, recipient
        assert_includes html, 'target="notifications_panel"'
        assert_includes html, notification.message
      end
      assert_equal read_at, notification.reload.read_at
    end
  end
end
