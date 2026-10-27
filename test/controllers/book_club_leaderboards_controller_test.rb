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
    assert_select ".book-club-podium-column--first .book-club-podium-label", count: 0
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

  test "leaderboard frame refresh returns updated rankings and the signed in reader highlight" do
    club = BookClub.create!(name: "Refresh ranking", current_book: books(:refactoring))
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")
    session = ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current, pages_read: 20)
    sign_in users(:leika)
    frame_id = dom_id(club, :leaderboard_frame)
    path = book_club_leaderboard_path(club)

    get path

    assert_response :success
    assert_select "a[href='#{path}'][data-turbo-frame='#{frame_id}'][data-turbo-prefetch='false']", text: "↻ Refresh leaderboard"
    assert_select "turbo-frame##{frame_id}[target='_top']" do
      assert_select ".book-club-ranking-row", count: 2
      assert_select "turbo-cable-stream-source", count: 0
    end
    assert_select "turbo-cable-stream-source", count: 1

    session.update!(pages_read: 75)
    get path, headers: { "Turbo-Frame" => frame_id }

    assert_response :success
    assert_select "turbo-frame##{frame_id}" do
      assert_select ".book-club-ranking-row:first-child" do
        assert_select "strong", text: users(:jaina).nickname
        assert_select ".book-club-ranking-pages", text: "75"
      end
      assert_select ".book-club-ranking-row--current", count: 1 do
        assert_select "strong", text: users(:leika).nickname
      end
    end
  end

  test "leaderboard frame refresh denies former members and guests" do
    club = BookClub.create!(name: "Private ranking", current_book: books(:refactoring))
    membership = club.book_club_memberships.create!(user: users(:leika), role: "owner")
    sign_in users(:leika)
    membership.destroy!
    headers = { "Turbo-Frame" => dom_id(club, :leaderboard_frame) }

    get book_club_leaderboard_path(club), headers: headers

    assert_redirected_to root_path
    assert_select "turbo-frame", count: 0

    sign_out users(:leika)
    get book_club_leaderboard_path(club), headers: headers

    assert_redirected_to new_user_session_path
    assert_select "turbo-frame", count: 0
  end

  test "podium and ranking show uploaded photos and fall back to the first two nickname characters" do
    club = BookClub.create!(name: "Avatar ranking", current_book: books(:refactoring))
    photo_reader = users(:leika)
    initials_reader = users(:jaina)
    club.book_club_memberships.create!(user: photo_reader, role: "owner")
    club.book_club_memberships.create!(user: initials_reader, role: "member")
    photo_reader.avatar.attach(io: File.open(file_fixture("cover_test.jpg")), filename: "avatar.jpg", content_type: "image/jpeg")
    ReadingSession.create!(user: initials_reader, book: books(:refactoring), read_on: Date.current, pages_read: 50)
    sign_in photo_reader

    get book_club_leaderboard_path(club)

    assert_response :success
    [ ".book-club-podium-avatar", ".book-club-ranking-avatar" ].each do |selector|
      assert_select "#{selector} .profile-avatar[aria-label='#{photo_reader.nickname} profile photo']" do
        assert_select "img.profile-avatar-image[src*='avatar.jpg']", count: 1
        assert_select ".profile-avatar-initials", count: 0
      end
      assert_select "#{selector} .profile-avatar[aria-label='#{initials_reader.nickname} profile photo']" do
        assert_select ".profile-avatar-initials", text: initials_reader.nickname.first(2).upcase
        assert_select "img", count: 0
      end
    end
    assert_select ".book-club-podium-avatar--empty", text: "—", count: 1
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
