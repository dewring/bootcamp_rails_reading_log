require "test_helper"

class BookClubsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest cannot create a book club" do
    post book_clubs_path, params: { book_club: { name: "Sci-Fi Society" } }
    assert_redirected_to new_user_session_path
  end

  test "creating a club makes the creator its owner" do
    sign_in users(:leika)

    post book_clubs_path, params: { book_club: { name: "Sci-Fi Society", description: "Space and robots." } }
    book_club = BookClub.find_by!(name: "Sci-Fi Society")

    assert_redirected_to book_club_path(book_club)
    assert book_club.book_club_memberships.exists?(user: users(:leika), role: "owner")
  end

  test "a user can join a club they are not a member of" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:jaina)
    post join_book_club_path(book_club)

    assert_redirected_to book_club_path(book_club)
    assert book_club.book_club_memberships.exists?(user: users(:jaina), role: "member")
  end

  test "book club browse renders current pick details and membership actions" do
    book_club = BookClub.create!(name: "Sci-Fi Society", description: "Space and robots.", current_book: books(:refactoring))
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    book_club.book_club_memberships.create!(user: users(:jaina), role: "member")

    sign_in users(:jaina)
    get book_clubs_path

    assert_response :success
    assert_select ".book-clubs-introduction h1", text: "Book clubs"
    assert_select ".book-clubs-filter", text: /All clubs · 1/
    assert_select ".book-club-directory-card h2 a", text: "Sci-Fi Society"
    assert_select ".book-club-directory-meta", text: /Current pick · Refactoring/
    assert_select ".book-club-status-badge", text: "Joined club"
    assert_select "a.book-club-action", text: "View Club"
  end

  test "joining a club a user is already a member of is rejected" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:leika)
    post join_book_club_path(book_club)

    assert_response :redirect
    assert_equal 1, book_club.book_club_memberships.where(user: users(:leika)).count
  end

  test "a member can leave a club" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    book_club.book_club_memberships.create!(user: users(:jaina), role: "member")

    sign_in users(:jaina)
    delete leave_book_club_path(book_club)

    assert_redirected_to book_clubs_path
    assert_not book_club.book_club_memberships.exists?(user: users(:jaina))
  end

  test "a non-member cannot leave a club" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:jaina)
    delete leave_book_club_path(book_club)

    assert_response :redirect
  end

  test "a club owner can set the current pick" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:leika)
    patch set_current_book_book_club_path(book_club), params: { book_club: { current_book_id: books(:refactoring).id } }

    assert_redirected_to book_club_path(book_club)
    assert_equal books(:refactoring), book_club.reload.current_book
  end

  test "show renders the overview shell and keeps the owner form available" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:leika)
    get book_club_path(book_club)

    assert_response :success
    assert_select "article##{ActionView::RecordIdentifier.dom_id(book_club, :current_pick)}"
    assert_select ".book-club-sidebar-navigation a", text: "Overview"
    assert_select ".book-club-sidebar-navigation a", text: "Leaderboard"
    assert_select ".book-club-stat-card", count: 3
    assert_select "li#notifications_panel"
    assert_select "turbo-cable-stream-source"
    assert_select "form[action='#{set_current_book_book_club_path(book_club)}']"
  end

  test "leaderboard view is available from the club detail shell" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:leika)
    get book_club_path(book_club, view: "leaderboard")

    assert_response :success
    assert_select "h1", text: "Leaderboard"
    assert_select ".book-club-sidebar-navigation a.is-active", text: "Leaderboard"
    assert_select ".book-club-podium-card"
    assert_select ".book-club-ranking-card"
    assert_select ".book-club-reading-rail"
    assert_select ".book-club-ranking-row", count: 1
  end

  test "a non-owner member cannot set the current pick" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    book_club.book_club_memberships.create!(user: users(:jaina), role: "member")

    sign_in users(:jaina)
    patch set_current_book_book_club_path(book_club), params: { book_club: { current_book_id: books(:refactoring).id } }

    assert_response :redirect
    assert_nil book_club.reload.current_book
  end
end
