require "test_helper"

class BookClubPolicyTest < ActiveSupport::TestCase
  def setup
    @book_club = BookClub.create!(name: "Sci-Fi Society")
    @owner = users(:leika)
    @member = users(:jaina)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
  end

  test "club owner can manage the club" do
    assert BookClubPolicy.new(@owner, @book_club).manage?
  end

  test "non-owner member cannot manage the club" do
    refute BookClubPolicy.new(@member, @book_club).manage?
  end

  test "site-wide admin who is only a club member still cannot manage the club" do
    admin = users(:admin)
    @book_club.book_club_memberships.create!(user: admin, role: "member")

    refute BookClubPolicy.new(admin, @book_club).manage?, "manage? must check BookClubMembership, not User#role"
  end

  test "guest cannot manage the club" do
    refute BookClubPolicy.new(nil, @book_club).manage?
  end

  test "non-member can join" do
    outsider = users(:admin)
    assert BookClubPolicy.new(outsider, @book_club).join?
  end

  test "existing member cannot join again" do
    refute BookClubPolicy.new(@member, @book_club).join?
  end

  test "member can leave" do
    assert BookClubPolicy.new(@member, @book_club).leave?
  end

  test "non-member cannot leave" do
    outsider = users(:admin)
    refute BookClubPolicy.new(outsider, @book_club).leave?
  end
end
