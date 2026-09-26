require "test_helper"

class NotificationPolicyTest < ActiveSupport::TestCase
  setup do
    @book_club = BookClub.create!(name: "Sci-Fi Society")
    @owner_notification = create_notification(users(:leika))
    @member_notification = create_notification(users(:jaina))
  end

  test "users can update only their own notifications" do
    assert NotificationPolicy.new(users(:leika), @owner_notification).update?
    assert_not NotificationPolicy.new(users(:jaina), @owner_notification).update?
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
