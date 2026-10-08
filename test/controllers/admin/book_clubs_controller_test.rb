require "test_helper"

class Admin::BookClubsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @club = BookClub.create!(name: "Sci-Fi Society", description: "Space and robots", current_book: books(:refactoring))
    @club.book_club_memberships.create!(user: users(:leika), role: "owner")
    @club.book_club_memberships.create!(user: users(:jaina), role: "member")
  end

  test "guests and regular users cannot use workspace management" do
    [ nil, users(:leika) ].each do |reader|
      sign_in reader if reader
      get admin_book_clubs_path
      assert_redirected_to(reader ? root_path : new_user_session_path)
      assert_no_difference("BookClub.count") { post admin_book_clubs_path, params: { book_club: { name: "Unauthorized" } } }
      patch admin_book_club_path(@club), params: { book_club: { name: "Unauthorized" } }
      assert_equal "Sci-Fi Society", @club.reload.name
      assert_no_difference("BookClub.count") { delete admin_book_club_path(@club) }
    end
  end

  test "workspace displays actual owner current pick and member count" do
    sign_in users(:admin)
    get admin_book_clubs_path, params: { club_id: @club.id }
    assert_response :success
    assert_select "h1", text: "Book Club Management"
    assert_select ".admin-club-record.is-selected strong", text: @club.name
    assert_select "input#admin_club_owner[readonly][value='martita']"
    assert_select "input#admin_club_members[readonly][value='2 members']"
    assert_select "input#book_club_current_book_id[type='hidden'][value='#{books(:refactoring).id}']"
    assert_select "input#admin_club_current_book_search[role='combobox'][value='Refactoring · Martin Fowler']"
    assert_select "#admin-club-book-results[hidden][role='listbox']"
    assert_select ".admin-club-deadline input[type='date']"
    assert_select "input#book_club_name[value='Sci-Fi Society']"
    assert_select ".admin-club-actions a", text: "View", count: 1
    assert_select ".admin-club-actions a", text: "Edit", count: 0
    assert_select ".admin-club-actions button", text: "Delete", count: 1
    assert_select ".admin-club-select[href*='club_id=#{@club.id}']"
    assert_select ".admin-sidebar-nav .is-active[aria-current='page']", text: "Book Clubs"
    assert_select "label", text: "Status", count: 0
  end

  test "book search requires admin and returns bounded title author matches with distinct IDs" do
    get search_books_admin_book_clubs_path, params: { q: "Refactoring" }
    assert_redirected_to new_user_session_path
    sign_in users(:leika)
    get search_books_admin_book_clubs_path, params: { q: "Refactoring" }
    assert_redirected_to root_path
    sign_in users(:admin)
    duplicate = Book.create!(title: "Refactoring", author: "Another writer")
    get search_books_admin_book_clubs_path, params: { q: "refactoring" }, as: :json
    assert_response :success
    assert_equal [ duplicate.id, books(:refactoring).id ].sort, response.parsed_body["books"].map { |book| book["id"] }.sort
    get search_books_admin_book_clubs_path, params: { q: "MARTIN FOWLER" }, as: :json
    assert_equal [ books(:refactoring).id ], response.parsed_body["books"].map { |book| book["id"] }
    12.times { |index| Book.create!(title: "Bounded search #{index}", author: "Writer") }
    get search_books_admin_book_clubs_path, params: { q: "Bounded search" }, as: :json
    assert_equal 10, response.parsed_body["books"].length
    [ "", "   ", "%", "_", "no matching book" ].each do |query|
      get search_books_admin_book_clubs_path, params: { q: query }, as: :json
      assert_empty response.parsed_body["books"]
    end
  end

  test "compact sort dropdown preserves search and selects the requested ordering" do
    sign_in users(:admin)
    get admin_book_clubs_path, params: { q: "Sci-Fi", sort: "name", club_id: @club.id }

    assert_response :success
    assert_select ".admin-clubs-sort-filter button[aria-expanded='false'][aria-controls='admin-clubs-sort-menu']", text: "Club name"
    assert_select "nav#admin-clubs-sort-menu[hidden] a", count: 2
    assert_select "nav#admin-clubs-sort-menu a[aria-current='true']", text: "Club name"
    assert_select "nav#admin-clubs-sort-menu a" do |links|
      links.each do |link|
        query = Rack::Utils.parse_query(URI.parse(link["href"]).query)
        assert_equal "Sci-Fi", query["q"]
        assert_equal (link.text == "Club name" ? "name" : "updated"), query["sort"]
        assert_nil query["page"]
        assert_nil query["club_id"]
      end
    end
    assert_select "a.admin-clubs-filter", text: "All records"

    get admin_book_clubs_path
    assert_select "nav#admin-clubs-sort-menu a[aria-current='true']", text: "Recently updated"
  end

  test "search matches club description owner and current book without duplicate clubs" do
    sign_in users(:admin)
    BookClub.create!(name: "Other club")
    [ "SCI-FI", "robots", "martita", "refactoring", "martin fowler" ].each do |query|
      get admin_book_clubs_path, params: { q: query }
      assert_response :success
      assert_select ".admin-club-record", count: 1
      assert_select ".admin-club-record strong", text: @club.name
    end
    get admin_book_clubs_path, params: { q: "no matching phrase" }
    assert_select ".admin-clubs-empty h2", text: "No matching clubs"
    assert_select ".admin-club-detail-empty"
  end

  test "pagination retains search and sort at the fifth club" do
    sign_in users(:admin)
    4.times { |index| BookClub.create!(name: "Sci-Fi #{index}") }
    get admin_book_clubs_path, params: { q: "Sci-Fi", sort: "name" }
    assert_select ".admin-club-record", count: 4
    assert_select ".admin-clubs-pagination .pagy.series-nav a[href*='page=2'][href*='q=Sci-Fi'][href*='sort=name']"
    get admin_book_clubs_path, params: { q: "Sci-Fi", sort: "name", page: 2 }
    assert_select ".admin-club-record", count: 1
  end

  test "new club form and validation errors preserve entered values" do
    sign_in users(:admin)
    get admin_book_clubs_path, params: { new_club: true }
    assert_select "h2#admin-club-detail-title", text: "Create a club"
    assert_select "input#admin_club_owner[value='theadmin']"
    assert_select "input[type='submit'][value='Create Club']"
    assert_no_difference("BookClub.count") do
      post admin_book_clubs_path, params: { book_club: { name: "", description: "Keep this description" } }
    end
    assert_response :unprocessable_entity
    assert_select ".admin-club-errors", text: /Name can't be blank/
    assert_select "textarea#book_club_description", text: "Keep this description"
  end

  test "admin creates a club with an owner membership" do
    sign_in users(:admin)
    assert_difference("BookClub.count", 1) do
      post admin_book_clubs_path, params: { book_club: { name: "Admin community", description: "Read together", current_book_id: books(:pragmatic).id, reading_deadline: "2026-12-01" } }
    end
    club = BookClub.find_by!(name: "Admin community")
    assert_redirected_to admin_book_clubs_path(club_id: club.id)
    assert club.book_club_memberships.exists?(user: users(:admin), role: "owner")
    assert_equal books(:pragmatic), club.current_book
  end

  test "admin edits another owners club without changing ownership and preserves live pick behavior" do
    sign_in users(:admin)
    clear_enqueued_jobs
    patch admin_book_club_path(@club), params: { q: "Sci-Fi", sort: "name", book_club: { name: "Sci-Fi readers", current_book_id: books(:pragmatic).id, reading_deadline: "2026-12-01", owner_id: users(:admin).id } }
    assert_redirected_to admin_book_clubs_path(club_id: @club.id, q: "Sci-Fi", sort: "name")
    assert_equal "Sci-Fi readers", @club.reload.name
    assert_equal books(:pragmatic), @club.current_book
    assert_equal Date.new(2026, 12, 1), @club.reading_deadline
    assert @club.book_club_memberships.exists?(user: users(:leika), role: "owner")
    assert_equal 2, @club.book_club_memberships_count
    assert_enqueued_with(job: BookClubCurrentPickJob, args: [ @club.id ])
    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ @club.id ])
    assert_enqueued_with(job: Noticed::EventJob)
  end

  test "invalid update preserves the editing panel and does not change the club" do
    sign_in users(:admin)
    patch admin_book_club_path(@club), params: { book_club: { name: "", description: "Unsaved description" } }
    assert_response :unprocessable_entity
    assert_select ".admin-club-errors", text: /Name can't be blank/
    assert_select "textarea#book_club_description", text: "Unsaved description"
    assert_equal "Sci-Fi Society", @club.reload.name
  end

  test "admin deletes another owners club and its memberships" do
    sign_in users(:admin)
    assert_difference("BookClub.count", -1) do
      assert_difference("BookClubMembership.count", -2) do
        delete admin_book_club_path(@club), params: { q: "Sci-Fi", sort: "name" }
      end
    end
    assert_redirected_to admin_book_clubs_path(q: "Sci-Fi", sort: "name")
  end
end
