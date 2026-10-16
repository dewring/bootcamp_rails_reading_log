require "test_helper"

class BookClubLeaderboardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "leaderboard route uses the dedicated controller and club id" do
    assert_routing({ method: "get", path: "/book_clubs/1/leaderboard" }, {
      controller: "book_club_leaderboards",
      action: "show",
      book_club_id: "1"
    })
  end

  test "leaderboard view is available from the club detail shell" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:leika)
    leaderboard_path = book_club_leaderboard_path(book_club)
    get leaderboard_path

    assert_response :success
    assert_select "h1", text: "Leaderboard"
    assert_select ".book-club-sidebar-navigation a.is-active[href='#{leaderboard_path}']", text: "Leaderboard"
    assert_select ".book-club-sidebar-navigation a.is-active", count: 1
    assert_select ".book-club-podium-card"
    assert_select ".book-club-ranking-card"
    assert_select ".book-club-reading-rail"
    assert_select ".book-club-ranking-row", count: 1
  end

  test "refresh requests recalculate leaderboard data and highlight each viewer separately" do
    club = BookClub.create!(name: "Live Ranking", current_book: books(:refactoring))
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current, pages_read: 50)
    viewers = [ users(:leika), users(:jaina) ]

    viewers.each do |viewer|
      sign_in viewer
      get book_club_leaderboard_path(club)
      assert_response :success
      assert_select "meta[name='turbo-refresh-method'][content='morph']"
      assert_select "meta[name='turbo-refresh-scroll'][content='preserve']"
      assert_select ".book-club-ranking-row", count: 2
      assert_select ".book-club-ranking-row--current", count: 1 do
        assert_select "strong", text: viewer.nickname
      end
      assert_select ".book-club-ranking-row:first-child .book-club-ranking-pages", text: "50"
      sign_out viewer
    end
  end

  test "guests are redirected to sign in" do
    club = BookClub.create!(name: "Discussion circle")

    get book_club_leaderboard_path(club)

    assert_redirected_to new_user_session_path
  end

  test "ordinary nonmembers cannot request leaderboard directly" do
    club = BookClub.create!(name: "Discussion circle")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    sign_in users(:jaina)

    get book_club_leaderboard_path(club)

    assert_redirected_to root_path

    get book_club_leaderboard_path(club), as: :json

    assert_response :forbidden
    assert_equal({ "error" => "Forbidden" }, response.parsed_body)
  end

  test "nonmember admin can view the leaderboard" do
    club = BookClub.create!(name: "Discussion circle")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    sign_in users(:admin)

    get book_club_leaderboard_path(club)

    assert_response :success
    assert_select "h1", text: "Leaderboard"
    assert_select ".book-club-member-status", text: "Administrator view"
  end
end
