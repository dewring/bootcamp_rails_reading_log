require "test_helper"

class BookClubReplyNotifierTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @recipient = users(:leika)
  end

  test "reply notifications use snapshot names and open discussion instead of overview" do
    event = create_reply_event
    @book_club.update!(name: "Renamed circle")
    notification = event.notifications.first.reload

    assert_equal "Reader replied to your discussion in Discussion circle.", notification.message
    assert_equal book_club_club_messages_path(@book_club), notification.url
    assert_equal @recipient, notification.recipient
    assert notification.unread?
  end

  test "deleted clubs retain reply notification text without a broken destination" do
    event = create_reply_event
    @book_club.destroy!
    notification = event.notifications.first.reload

    assert_equal "Reader replied to your discussion in Discussion circle.", notification.message
    assert_nil notification.url
  end

  test "reply delivery retries broadcast the saved notification without duplicating rows or resetting read state" do
    notification = create_reply_event.notifications.first
    travel_to(Time.utc(2026, 11, 7, 12).change(nsec: 123456789), with_usec: true) do
      notification.mark_as_read!
    end
    read_at = notification.reload.read_at
    broadcasts = []

    assert_no_difference [ "Noticed::Event.count", "Noticed::Notification.count" ] do
      Noticed::NotificationChannel.stub(:broadcast_to, ->(*args) { broadcasts.push(args) }) do
        2.times { Noticed::DeliveryMethods::ActionCable.new.perform(:action_cable, notification) }
      end
    end

    assert_equal 2, broadcasts.size
    broadcasts.each do |recipient, html|
      assert_equal @recipient, recipient
      assert_includes html, notification.message
      assert_includes html, 'target="notifications_panel"'
      assert_includes html, "href=\"#{book_club_club_messages_path(@book_club)}\""
    end
    assert_equal read_at, notification.reload.read_at
  end

  private

  def create_reply_event
    BookClubReplyNotifier.with(
      record: @book_club, book_club_name: @book_club.name, reply_author_name: "Reader"
    ).deliver(@recipient, enqueue_job: false)
  end
end
