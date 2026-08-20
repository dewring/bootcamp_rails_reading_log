require "test_helper"

class BookClubMembershipTest < ActiveSupport::TestCase
  def setup
    @book_club = BookClub.create!(name: "Sci-Fi Society")
  end

  test "valid membership is valid" do
    membership = BookClubMembership.new(book_club: @book_club, user: users(:leika), role: "member")
    assert membership.valid?
  end

  test "role must be owner or member" do
    membership = BookClubMembership.new(book_club: @book_club, user: users(:leika), role: "president")
    assert_not membership.valid?
  end

  test "user cannot join the same club twice" do
    BookClubMembership.create!(book_club: @book_club, user: users(:leika), role: "member")
    duplicate = BookClubMembership.new(book_club: @book_club, user: users(:leika), role: "member")

    assert_not duplicate.valid?
  end
end
