require "test_helper"

class BookClubCreatorTest < ActiveSupport::TestCase
  test "creates the club and owner together" do
    club = BookClub.new(name: "New community")
    result = BookClubCreator.new(book_club: club, owner: users(:admin)).create_club
    assert_equal club, result
    assert club.persisted?
    assert_equal 1, club.reload.book_club_memberships_count
    assert club.book_club_memberships.exists?(user: users(:admin), role: "owner")
  end

  test "owner membership failure rolls back the club" do
    club = BookClub.new(name: "Rolled back club")
    assert_no_difference("BookClub.count") do
      assert_raises(ActiveRecord::RecordInvalid) do
        BookClubCreator.new(book_club: club, owner: nil).create_club
      end
    end
    refute club.persisted?
  end
end
