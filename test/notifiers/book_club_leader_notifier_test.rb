require "test_helper"

class BookClubLeaderNotifierTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  setup do
    @club = BookClub.create!(name: "Leaderboard circle")
    @recipient = users(:leika)
  end

  test "a sole leader notification opens the leaderboard" do
    notification = create_event([ "Mina" ]).notifications.first

    assert_equal "Mina is now first in Leaderboard circle for A Book.", notification.message
    assert_equal book_club_leaderboard_path(@club), notification.url
    assert notification.unread?
  end

  test "tied leaders and an empty ranking have explicit notification messages" do
    assert_equal "Mina and Joon share first place in Leaderboard circle for A Book.",
      create_event([ "Mina", "Joon" ]).notifications.first.message
    assert_equal "Leaderboard circle has no ranked readers for A Book.", create_event([]).notifications.first.message
  end

  test "leader names club name and book title remain readable after the club is renamed and deleted" do
    event = create_event([ "Mina", "Joon" ])
    @club.update!(name: "Renamed circle")
    @club.destroy!
    notification = event.notifications.first.reload

    assert_equal "Mina and Joon share first place in Leaderboard circle for A Book.", notification.message
    assert_nil notification.url
  end

  test "leader delivery retries do not duplicate notifications or reset read state" do
    notification = create_event([ "Mina" ]).notifications.first
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
      assert_includes html, "href=\"#{book_club_leaderboard_path(@club)}\""
    end
    assert_equal read_at, notification.reload.read_at
  end

  private

  def create_event(names)
    BookClubLeaderNotifier.with(
      record: @club, book_club_name: @club.name, book_title: "A Book", leader_names: names
    ).deliver(@recipient, enqueue_job: false)
  end
end
