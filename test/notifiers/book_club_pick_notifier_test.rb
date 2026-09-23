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

  test "broadcasts the refreshed panel to the recipient notification stream" do
    event = BookClubPickNotifier.with(
      record: @book_club,
      book_club_name: @book_club.name,
      book_title: "The Left Hand of Darkness"
    ).deliver(@user, enqueue_job: false)
    notification = event.notifications.first
    broadcasts = []

    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*args, **options) { broadcasts << [ args, options ] }) do
      DeliveryMethods::TurboStream.new.perform(:turbo_stream, notification)
    end

    assert_equal [ @user, :notifications ], broadcasts.first.first
    assert_equal "notifications_panel", broadcasts.first.last[:target]
    assert_equal "notifications/panel", broadcasts.first.last[:partial]
    assert_equal({ user: @user }, broadcasts.first.last[:locals])
  end
end
