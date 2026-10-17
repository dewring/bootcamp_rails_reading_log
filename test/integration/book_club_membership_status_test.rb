require "test_helper"

class BookClubMembershipStatusTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "admin who creates a club is shown as its owner on every club page" do
    post admin_book_clubs_path, params: {
      book_club: { name: "Admin-owned circle", description: "Read together" }
    }
    club = BookClub.find_by!(name: "Admin-owned circle")

    assert_redirected_to admin_book_clubs_path(club_id: club.id)
    assert_status_on_club_pages(club, "You're the club owner", "Club owner")
  end

  test "admin without club membership is shown as an administrator on every club page" do
    club = BookClub.create!(name: "Another reader's circle")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")

    assert_status_on_club_pages(club, "Administrator view", "Admin")
  end

  test "admin who joins a club is shown as a member on every club page" do
    club = BookClub.create!(name: "Another reader's circle")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")

    post join_book_club_path(club)

    assert_redirected_to book_club_path(club)
    assert_status_on_club_pages(club, "You're a member", "Club member")
  end

  test "ordinary owner labels are consistent on every club page" do
    club = BookClub.create!(name: "Reader-owned circle")
    owner = users(:leika)
    club.book_club_memberships.create!(user: owner, role: "owner")
    sign_out @admin
    sign_in owner

    assert_status_on_club_pages(club, "You're the club owner", "Club owner")
  end

  test "ordinary member labels are consistent on every club page" do
    club = BookClub.create!(name: "Reader-owned circle")
    member = users(:jaina)
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: member, role: "member")
    sign_out @admin
    sign_in member

    assert_status_on_club_pages(club, "You're a member", "Club member")
  end

  test "ordinary nonmember can view only overview without membership labels or private navigation" do
    club = BookClub.create!(name: "Another reader's circle")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    sign_out @admin
    sign_in users(:jaina)

    get book_club_path(club)

    assert_response :success
    assert_select ".book-club-member-status", count: 0
    assert_select ".book-club-sidebar-account strong + span", count: 0
    assert_select ".book-club-sidebar-navigation a", text: "Overview", count: 1
    assert_select ".book-club-sidebar-navigation a", text: "Leaderboard", count: 0
    assert_select ".book-club-sidebar-navigation a", text: "Discussion", count: 0

    get book_club_leaderboard_path(club)

    assert_redirected_to root_path
    assert_select ".book-club-ranking-row", count: 0

    get book_club_leaderboard_path(club), as: :json

    assert_response :forbidden
    assert_equal({ "error" => "Forbidden" }, response.parsed_body)
  end

  test "ordinary member loses leaderboard access after leaving the club" do
    club = BookClub.create!(name: "Another reader's circle")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    membership = club.book_club_memberships.create!(user: users(:jaina), role: "member")
    sign_out @admin
    sign_in users(:jaina)

    get book_club_leaderboard_path(club)

    assert_response :success
    membership.destroy!

    get book_club_leaderboard_path(club)

    assert_redirected_to root_path
  end

  test "club sidebar marks only the current page for assistive technology" do
    club = BookClub.create!(name: "Accessible circle")
    club.book_club_memberships.create!(user: @admin, role: "owner")
    pages = [
      { path: book_club_path(club), label: "Overview" },
      { path: book_club_club_messages_path(club), label: "Discussion" },
      { path: book_club_leaderboard_path(club), label: "Leaderboard" }
    ]

    pages.each do |page|
      get page[:path]

      assert_response :success
      assert_select ".book-club-sidebar-navigation a[aria-current]", count: 1
      assert_select ".book-club-sidebar-navigation a.is-active[aria-current='page']", count: 1, text: page[:label]
    end
  end

  test "sidebar displays the club name without added initials on every club page" do
    club = BookClub.create!(name: "harry potter")
    paths = [
      book_club_path(club),
      book_club_club_messages_path(club),
      book_club_leaderboard_path(club)
    ]

    paths.each do |path|
      get path

      assert_response :success
      assert_select ".book-club-sidebar-identity h2", text: "harry potter", count: 1
    end
  end

  private

  def assert_status_on_club_pages(club, expected_status, expected_sidebar_label)
    paths = [
      book_club_path(club),
      book_club_club_messages_path(club),
      book_club_leaderboard_path(club)
    ]

    paths.each do |path|
      get path

      assert_response :success
      assert_select ".book-club-detail-header .book-club-member-status", count: 1, text: expected_status
      assert_select ".book-club-sidebar-account strong + span", count: 1, text: expected_sidebar_label
    end
  end
end
