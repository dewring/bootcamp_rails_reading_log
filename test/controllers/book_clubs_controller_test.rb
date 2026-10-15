require "test_helper"

class BookClubsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "club pick search requires sign in and returns five case insensitive title or author matches" do
    get search_books_book_clubs_path, params: { q: "Refactoring" }, as: :json
    assert_response :unauthorized

    [ users(:leika), users(:admin) ].each do |member|
      sign_in member
      [ "rEfAcToRiNg", "MARTIN FOWLER" ].each do |query|
        get search_books_book_clubs_path, params: { q: query }, as: :json
        assert_response :success
        assert_equal [ books(:refactoring).id ], response.parsed_body["books"].map { |book| book["id"] }
      end
      [ "", "   ", "%", "_" ].each do |query|
        get search_books_book_clubs_path, params: { q: query }, as: :json
        assert_empty response.parsed_body["books"]
      end
      sign_out member
    end

    8.times { |index| Book.create!(title: "Club search #{index}", author: "Writer") }
    sign_in users(:leika)
    get search_books_book_clubs_path, params: { q: "CLUB SEARCH" }, as: :json
    assert_equal 5, response.parsed_body["books"].length
  end

  test "regular and admin owners use the shared searchable pick and calendar fields" do
    [ users(:leika), users(:admin) ].each do |owner|
      club = BookClub.create!(name: "Owner #{owner.id}", current_book: books(:pragmatic), reading_deadline: "2026-12-01")
      club.book_club_memberships.create!(user: owner, role: "owner")
      sign_in owner
      get book_club_path(club)

      assert_response :success
      assert_select "#owner-controls [data-controller='club-book-search'][data-club-book-search-url-value='#{search_books_book_clubs_path}']"
      assert_select "#owner-controls input[role='combobox'][value='#{club.current_book.title} · #{club.current_book.author}']"
      assert_select "#owner-controls [role='listbox'][hidden]"
      assert_select "#owner-controls .club-reading-deadline input[type='date'][value='2026-12-01']"
      assert_select "#owner-controls datalist", count: 0
      assert_select ".book-club-sidebar a[href='#{edit_book_club_path(club)}']", count: 0
      assert_select "#owner-controls form[action='#{book_club_path(club)}']"
      assert_select "#owner-controls input[name='book_club[name]'][value='#{club.name}']"
      assert_select "#owner-controls textarea[name='book_club[description]']"
      assert_select "#owner-controls .form-submit a.club-owner-delete[href='#{book_club_path(club)}'][data-turbo-method='delete'][data-turbo-confirm]", text: "Delete book club"

      patch book_club_path(club), params: { book_club: { name: "Updated club", description: "Read together", current_book_id: books(:refactoring).id, reading_deadline: "2026-12-15" } }
      assert_redirected_to book_club_path(club)
      assert_equal books(:refactoring), club.reload.current_book
      assert_equal Date.new(2026, 12, 15), club.reading_deadline
      assert_equal "Updated club", club.name
      assert_equal "Read together", club.description
      sign_out owner
    end
  end

  test "invalid owner changes stay on overview with errors and preserve submitted fields" do
    club = BookClub.create!(name: "Original club", current_book: books(:pragmatic))
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    sign_in users(:leika)

    patch book_club_path(club), params: { book_club: { name: "", description: "Draft description", current_book_id: books(:refactoring).id, reading_deadline: "2026-12-15" } }

    assert_response :unprocessable_entity
    assert_select "#owner-controls [role='alert']", text: /Name can't be blank/
    assert_select "#owner-controls textarea[name='book_club[description]']", text: "Draft description"
    assert_select "#owner-controls input[type='date'][value='2026-12-15']"
    assert_select "#owner-controls input[role='combobox'][value='Refactoring · Martin Fowler']"
    assert_equal "Original club", club.reload.name
    assert_equal books(:pragmatic), club.current_book
  end

  test "non-owner cannot edit club details through the overview form" do
    club = BookClub.create!(name: "Original club", description: "Original description", current_book: books(:pragmatic))
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")
    sign_in users(:jaina)
    get book_club_path(club)
    assert_select "#owner-controls", count: 0

    patch book_club_path(club), params: { book_club: { name: "Changed", description: "Changed", current_book_id: books(:refactoring).id, reading_deadline: "2026-12-15" } }

    assert_redirected_to root_path
    assert_equal "Original club", club.reload.name
    assert_equal "Original description", club.description
    assert_equal books(:pragmatic), club.current_book
    assert_nil club.reading_deadline
  end

  test "regular and admin club owners can delete their club" do
    [ users(:leika), users(:admin) ].each do |owner|
      club = BookClub.create!(name: "Owner deletion #{owner.id}")
      club.book_club_memberships.create!(user: owner, role: "owner")
      sign_in owner

      assert_difference "BookClub.count", -1 do
        delete book_club_path(club)
      end

      assert_redirected_to book_clubs_path
      assert_not BookClubMembership.exists?(book_club_id: club.id)
      sign_out owner
    end
  end

  test "a non-owner cannot see or use club deletion" do
    club = BookClub.create!(name: "Protected club")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    [ users(:jaina), users(:admin) ].each do |non_owner|
      sign_in non_owner
      get book_club_path(club)
      assert_select "a.club-owner-delete", count: 0

      assert_no_difference "BookClub.count" do
        delete book_club_path(club)
      end
      assert_redirected_to root_path
      sign_out non_owner
    end
  end

  test "guest cannot create a book club" do
    post book_clubs_path, params: { book_club: { name: "Sci-Fi Society" } }
    assert_redirected_to new_user_session_path
  end

  test "Create Book Club opens the overview creation mode without existing-club statistics" do
    sign_in users(:leika)
    get book_clubs_path
    assert_response :success
    assert_select "a[href='#{book_clubs_path(new_club: true)}']", text: "Create Book Club"
    assert_select "a[href='#{new_book_club_path}']", count: 0

    get book_clubs_path(new_club: true)
    assert_response :success
    assert_select ".book-club-detail-page h1", text: "Overview"
    assert_select ".book-club-sidebar-navigation a.is-active", text: "Overview"
    assert_select ".book-club-stat-grid, .book-club-member-status, .book-club-member-list", count: 0
    assert_select "input[readonly]", count: 0
    assert_select "form[action='#{book_clubs_path}']" do
      assert_select "input[name='book_club[name]'][required]"
      assert_select "textarea[name='book_club[description]'][required]"
      assert_select "input[name='book_club[current_book_id]']"
      assert_select "input[name='book_club[reading_deadline]']:not([required])"
      assert_select "[data-controller='club-book-search']"
    end

    get new_book_club_path
    assert_redirected_to book_clubs_path(new_club: true)
  end

  test "creation without a pick or deadline succeeds and opens the new club overview" do
    sign_in users(:leika)
    assert_difference("BookClub.count", 1) do
      post book_clubs_path, params: { book_club: { name: "Optional Pick", description: "Read at your own pace.", current_book_id: "", reading_deadline: "" } }
    end
    club = BookClub.find_by!(name: "Optional Pick")
    assert_nil club.current_book_id
    assert_nil club.reading_deadline
    assert_redirected_to book_club_path(club)
    follow_redirect!
    assert_select "h1", text: "Overview"
    assert_select ".book-club-member-status", text: "You're the club owner"
  end

  test "creation saves optional pick and deadline using the existing book search fields" do
    sign_in users(:leika)
    deadline = 7.days.from_now.to_date
    post book_clubs_path, params: { book_club: { name: "Chosen Pick", description: "A shared reading cycle.", current_book_id: books(:refactoring).id, reading_deadline: deadline } }
    club = BookClub.find_by!(name: "Chosen Pick")
    assert_equal books(:refactoring), club.current_book
    assert_equal deadline, club.reading_deadline
    assert_redirected_to book_club_path(club)
  end

  test "blank required creation fields render errors and preserve optional selections without creating an owner" do
    sign_in users(:leika)
    [ { name: "", description: "A description" }, { name: "Retained Name", description: "   " } ].each do |attributes|
      assert_no_difference([ "BookClub.count", "BookClubMembership.count" ]) do
        post book_clubs_path, params: { book_club: attributes.merge(current_book_id: books(:refactoring).id, reading_deadline: "2026-12-01") }
      end
      assert_response :unprocessable_entity
      assert_select ".book-club-detail-page h1", text: "Overview"
      assert_select "[role='alert']", text: /can't be blank/
      assert_select "input[name='book_club[name]'][value='#{attributes[:name]}']"
      assert_select "input[name='book_club[current_book_id]'][value='#{books(:refactoring).id}']"
      assert_select "input[name='book_club[reading_deadline]'][value='2026-12-01']"
    end
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

  test "overview and leaderboard labels reflect the current user's club membership role" do
    club = BookClub.create!(name: "Role Labels", current_book: books(:refactoring))
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")

    [ [ users(:leika), "You're the club owner" ],
      [ users(:jaina), "You're a member" ],
      [ users(:admin), nil ] ].each do |viewer, label|
      sign_in viewer
      [ nil, "leaderboard" ].each do |view|
        get book_club_path(club), params: { view: view }
        assert_response :success
        if label
          assert_select ".book-club-member-status", text: label, count: 1
        else
          assert_select ".book-club-member-status", count: 0
        end
      end
      sign_out viewer
    end
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
    assert_select "#owner-controls form[action='#{book_club_path(book_club)}']"
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

  test "refresh requests show the latest pick and preserve viewer-specific management controls" do
    club = BookClub.create!(name: "Live Pick", current_book: books(:refactoring))
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")
    club.update!(current_book: books(:pragmatic))

    [ [ users(:leika), 1 ], [ users(:jaina), 0 ] ].each do |viewer, controls|
      sign_in viewer
      get book_club_path(club)
      assert_response :success
      assert_select "meta[name='turbo-refresh-method'][content='morph']"
      assert_select "meta[name='turbo-refresh-scroll'][content='preserve']"
      assert_select ".book-club-current-pick-information h2", text: books(:pragmatic).title
      assert_select ".book-club-current-pick-card a[href='#{edit_book_club_path(club)}']", text: "Change Pick", count: controls
      sign_out viewer
    end
  end

  test "refresh requests recalculate leaderboard data and highlight each viewer separately" do
    club = BookClub.create!(name: "Live Ranking", current_book: books(:refactoring))
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current, pages_read: 50)

    [ users(:leika), users(:jaina) ].each do |viewer|
      sign_in viewer
      get book_club_path(club, view: "leaderboard")
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
