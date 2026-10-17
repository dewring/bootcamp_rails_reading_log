require "test_helper"

class ClubDiscussionChannelTest < ActionCable::Channel::TestCase
  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
  end

  test "club owner can subscribe to the club discussion" do
    stub_connection current_user: @owner

    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_has_stream_for @book_club
  end

  test "club member can subscribe to the club discussion" do
    stub_connection current_user: @member

    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_has_stream_for @book_club
  end

  test "nonmember admin can subscribe to the club discussion" do
    stub_connection current_user: @admin

    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_has_stream_for @book_club
  end

  test "ordinary nonmember cannot subscribe" do
    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    stub_connection current_user: @member

    subscribe book_club_id: @book_club.id

    assert subscription.rejected?
    assert_no_streams
  end

  test "membership in another club does not grant discussion access" do
    other_club = BookClub.create!(name: "Another circle")
    stub_connection current_user: @member

    subscribe book_club_id: other_club.id

    assert subscription.rejected?
    assert_no_streams
  end

  test "guest cannot subscribe" do
    stub_connection current_user: nil

    subscribe book_club_id: @book_club.id

    assert subscription.rejected?
    assert_no_streams
  end

  test "missing club is rejected" do
    stub_connection current_user: @admin

    subscribe book_club_id: nil

    assert subscription.rejected?
    assert_no_streams
  end
end
