require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "anonymous homepage loads eight trending books ordered by score and recency" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    candidates = 9.times.map do |index|
      book = Book.create!(title: "Trending #{index}", author: "Test author")
      Reaction.create!(book: book, user: users(:leika), kind: "dislike", updated_at: as_of - (index + 1).hours)
      book
    end
    Reaction.create!(book: candidates.last, user: users(:jaina), kind: "love", updated_at: as_of - 1.day)

    travel_to(as_of) do
      get root_path

      assert_response :success
      assert_equal [ candidates.last.id, *candidates.first(7).map(&:id) ], assigns(:trending_books).map(&:id)
      assert_select ".home-trending .home-view-all, .home-trending nav, .home-trending button", count: 0
      assert_select ".home-trending a.book-card", count: 8
      assert_select ".home-trending turbo-cable-stream-source", count: 0
    end
  end

  test "trending cards preload and render covers without external requests" do
    candidates = 2.times.map do |index|
      book = Book.create!(title: "Trending cover #{index}", author: "Test author")
      book.cover_image.attach(fixture_file_upload("cover_test.jpg", "image/jpeg"))
      Reaction.create!(book: book, user: users(:leika), kind: "like", updated_at: 1.hour.ago)
      book
    end

    get root_path

    assert_response :success
    assert_select ".home-trending img.book-cover", count: 2
    assert_equal candidates.map(&:id).sort, assigns(:trending_books).map(&:id).sort
    assigns(:trending_books).each do |book|
      assert book.association(:cover_image_attachment).loaded?
      assert book.cover_image_attachment.association(:blob).loaded?
      assert book.cover_image.blob.association(:variant_records).loaded?
    end
    assert_not_requested :any, /openlibrary\.org/
  end

  test "trending renders cached books again after their cover variant has been processed" do
    book = Book.create!(title: "Processed trending cover", author: "Test author")
    book.cover_image.attach(fixture_file_upload("cover_test.jpg", "image/jpeg"))
    Reaction.create!(book: book, user: users(:leika), kind: "like", updated_at: 1.hour.ago)
    get root_path
    assert_response :success

    book.cover_image.variant(resize_to_fill: [ 160, 240 ]).processed
    get root_path

    assert_response :success
    assert_select ".home-trending img.book-cover", count: 1
  end

  test "trending empty state offers the ordinary catalog without substituting unrelated books" do
    get root_path

    assert_response :success
    assert_select ".home-trending .empty-state", text: "No books have qualifying reactions in the last seven days."
    assert_select ".home-trending a[href='#{books_path}']", text: "Browse the ordinary book catalog"
    assert_select ".home-trending .book-card, .home-trending .home-view-all, .home-trending button", count: 0
  end

  test "private reading reviews and club discussion do not create trending candidates or appear in the section" do
    book = Book.create!(title: "Private activity book", author: "Test author")
    ReadingSession.create!(book: book, user: users(:leika), read_on: Date.current, pages_read: 10)
    review = book.reviews.create!(user: users(:leika), rating: 4, body: "Private review signal")
    review.reactions.create!(user: users(:jaina), kind: "like")
    club = BookClub.create!(name: "Private club identity")
    message = club.club_messages.create!(user: users(:leika), body: "Private discussion signal")
    message.reactions.create!(user: users(:jaina), kind: "love")

    get root_path

    assert_response :success
    assert_empty assigns(:trending_books)
    assert_select ".home-trending" do |sections|
      [ review.body, club.name, message.body, users(:leika).email, users(:leika).nickname ].each do |private_text|
        assert_not_includes sections.first.text, private_text
      end
    end
    assert_not_requested :any, /openlibrary\.org/
  end

  test "trending reuses the ranking for thirty minutes then recalculates the cutoff and candidates" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    Reaction.create!(book: books(:refactoring), user: users(:leika), kind: "like", updated_at: as_of - 7.days)

    assert_trending_query_count(1) do
      travel_to(as_of) { get root_path }
      assert_equal [ books(:refactoring).id ], assigns(:trending_books).map(&:id)
    end

    assert_trending_query_count(0) do
      travel_to(as_of + 30.minutes - 1.second) { get root_path }
      assert_equal [ books(:refactoring).id ], assigns(:trending_books).map(&:id)
    end

    assert_trending_query_count(1) do
      travel_to(as_of + 30.minutes) { get root_path }
      assert_empty assigns(:trending_books)
    end
  end

  test "committed new reactions change the ranking only after its thirty minute expiry" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    first = books(:refactoring)
    second = books(:pragmatic)
    Reaction.create!(book: first, user: users(:leika), kind: "dislike", updated_at: as_of - 1.hour)
    travel_to(as_of) { get root_path }
    assert_equal [ first.id ], assigns(:trending_books).map(&:id)
    Reaction.create!(book: second, user: users(:leika), kind: "love", updated_at: as_of + 1.minute)
    Reaction.create!(book: second, user: users(:jaina), kind: "wow", updated_at: as_of + 1.minute)

    assert_trending_query_count(0) do
      travel_to(as_of + 2.minutes) { get root_path }
      assert_equal [ first.id ], assigns(:trending_books).map(&:id)
    end
    assert_trending_query_count(1) do
      travel_to(as_of + 30.minutes) { get root_path }
      assert_equal [ second.id, first.id ], assigns(:trending_books).map(&:id)
    end
  end

  test "an empty trending result remains cached after a reaction until expiry" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    assert_trending_query_count(1) { travel_to(as_of) { get root_path } }
    Reaction.create!(book: books(:refactoring), user: users(:leika), kind: "like", updated_at: as_of + 1.minute)

    assert_trending_query_count(0) do
      travel_to(as_of + 2.minutes) { get root_path }
      assert_empty assigns(:trending_books)
    end
    assert_trending_query_count(1) do
      travel_to(as_of + 30.minutes) { get root_path }
      assert_equal [ books(:refactoring).id ], assigns(:trending_books).map(&:id)
    end
  end

  test "removing a tied book reaction preserves its cached rank while updating its total" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    first = books(:refactoring)
    second = books(:pragmatic)
    [ first, second ].each do |book|
      [ users(:leika), users(:jaina) ].each do |reader|
        Reaction.create!(book: book, user: reader, kind: "like", updated_at: as_of - 1.hour)
      end
    end

    travel_to(as_of) do
      get root_path
      assert_select ".home-trending .trending-rank[aria-label='Rank 1']", count: 2

      ReactionSelection.new(user: users(:jaina), target: second).clear_selection
      assert_trending_query_count(0) { get root_path }

      assert_select ".home-trending .trending-book-card" do |cards|
        remaining = cards.find { |card| card.at_css("a")["href"] == book_path(second) }
        assert_equal "Rank 1", remaining.at_css(".trending-rank")["aria-label"]
        assert_equal "Total reactions 1", remaining.at_css(".trending-total").text.strip
      end
      assert_equal 1, assigns(:trending_statistics).fetch(first.id).fetch(:rank)
      assert_equal 1, assigns(:trending_statistics).fetch(second.id).fetch(:rank)
    end
  end

  test "shared ranks and seven day counts refresh together after expiry" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    first = books(:refactoring)
    second = books(:pragmatic)
    Reaction.create!(book: first, user: users(:leika), kind: "like", updated_at: as_of - 2.hours)
    Reaction.create!(book: second, user: users(:leika), kind: "love", updated_at: as_of - 1.hour)

    travel_to(as_of) do
      get root_path

      assert_equal({ id: first.id, rank: 1, reaction_count: 1 }, assigns(:trending_statistics).fetch(first.id))
      assert_equal({ id: second.id, rank: 1, reaction_count: 1 }, assigns(:trending_statistics).fetch(second.id))
    end
    Reaction.create!(book: second, user: users(:jaina), kind: "wow", updated_at: as_of + 1.minute)

    travel_to(as_of + 2.minutes) do
      assert_trending_query_count(0) { get root_path }
      assert_equal 1, assigns(:trending_statistics).fetch(second.id).fetch(:reaction_count)
      assert_equal 1, assigns(:trending_statistics).fetch(first.id).fetch(:rank)
    end

    travel_to(as_of + 30.minutes) do
      assert_trending_query_count(1) { get root_path }
      assert_equal({ id: second.id, rank: 1, reaction_count: 2 }, assigns(:trending_statistics).fetch(second.id))
      assert_equal({ id: first.id, rank: 2, reaction_count: 1 }, assigns(:trending_statistics).fetch(first.id))
    end
  end

  test "cached trending IDs preserve order while current titles are loaded and deleted books are omitted" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    first = Book.create!(title: "First cached book", author: "Test author")
    second = Book.create!(title: "Second cached book", author: "Test author")
    Reaction.create!(book: first, user: users(:leika), kind: "like", updated_at: as_of - 2.hours)
    Reaction.create!(book: second, user: users(:leika), kind: "dislike", updated_at: as_of - 1.hour)
    travel_to(as_of) { get root_path }
    assert_equal [ second.id, first.id ], assigns(:trending_books).map(&:id)
    second.update!(title: "Updated cached book")

    assert_trending_query_count(0) do
      travel_to(as_of + 1.minute) { get root_path }
      assert_equal [ second.id, first.id ], assigns(:trending_books).map(&:id)
      assert_select ".home-trending .book-title", text: "Updated cached book"
    end
    first.destroy!
    assert_trending_query_count(0) do
      travel_to(as_of + 2.minutes) { get root_path }
      assert_equal [ second.id ], assigns(:trending_books).map(&:id)
      assert_response :success
    end
  end

  test "loading shared cached trending IDs still applies the book policy scope" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    first = books(:refactoring)
    second = books(:pragmatic)
    Reaction.create!(book: first, user: users(:leika), kind: "like", updated_at: as_of - 2.hours)
    Reaction.create!(book: second, user: users(:leika), kind: "dislike", updated_at: as_of - 1.hour)
    restricted_scope = Minitest::Mock.new
    restricted_scope.expect(:resolve, Book.where(id: first.id))

    travel_to(as_of) do
      assert_trending_query_count(1) { get root_path }
      assert_equal [ second.id, first.id ], assigns(:trending_books).map(&:id)

      BookPolicy::Scope.stub(:new, restricted_scope) do
        assert_trending_query_count(0) { get root_path }
        assert_equal [ first.id ], assigns(:trending_books).map(&:id)
        assert_equal [ first.id ], assigns(:trending_statistics).keys
      end
      restricted_scope.verify

      assert_trending_query_count(0) { get root_path }
      assert_equal [ second.id, first.id ], assigns(:trending_books).map(&:id)
    end
  end

  test "the default trending shelf precedes other shelves and shows ranks and total reactions for guests and readers" do
    book = books(:refactoring)
    Reaction.create!(book: book, user: users(:leika), kind: "dislike", updated_at: 1.hour.ago)

    [ nil, users(:jaina) ].each do |viewer|
      sign_in viewer if viewer
      get root_path

      assert_response :success
      assert_select "section.home-section > header > h2" do |headings|
        assert_equal [ "Trending", "Most Read", "New Books" ], headings.map(&:text)
      end
      assert_select ".home-trending .trending-book-card > a.book-card[href='#{book_path(book)}']", count: 1
      assert_select ".home-trending .book-title", text: book.title
      assert_select ".home-trending .book-author", text: book.author
      assert_select ".home-trending > p, .home-trending time, .home-trending .reaction-panel, .home-trending turbo-cable-stream-source, .home-trending .home-view-all", count: 0
      assert_select ".home-trending .book-row > :not(article.trending-book-card)", count: 0
      assert_select ".home-trending .trending-rank[aria-label='Rank 1']", count: 1
      assert_select ".home-trending .trending-total", text: "Total reactions 1"
      assert_select ".home-trending" do |sections|
        [ "Rank ", "7-day reactions", "All-date reactions", "Each active reader", "7-day window" ].each do |removed_text|
          assert_not_includes sections.first.text, removed_text
        end
      end
    end
  end

  test "homepage loads successfully" do
    get root_path

    assert_response :success
    assert_select "section.home-hero[aria-labelledby='home-hero-title']"
    assert_select "h1#home-hero-title", "Summer Reading Challenge — Join Now"
    assert_select "section.home-section", count: 3
    assert_select "h2", text: "Most Read"
    assert_select "h2", text: "New Books"
    assert_select "a.home-view-all[href='#{books_path(filter: 'most_read')}']", count: 1
    assert_select "a.home-view-all[href='#{books_path(filter: 'new_books')}']", count: 1
    assert_select "footer.home-footer"
    assert_select "button.nav-account-trigger[aria-label='Account'][aria-expanded='false'] img.account-icon"
    assert_select "button.nav-menu-trigger[aria-label='Menu'][aria-expanded='false'] img.nav-action-icon"
    assert_select "li.nav-menu[data-action*='mouseenter->nav-menu#enter'][data-action*='mouseleave->nav-menu#leave']"
    assert_select "li.account-menu[data-action*='mouseenter->account-dropdown#enter'][data-action*='mouseleave->account-dropdown#leave']"
    assert_select "ul#nav_menu_dropdown[hidden] li a[href='#{books_path}']", text: "Catalog"
    assert_select "ul#account_dropdown[hidden] li a", count: 2
    assert_select "ul#account_dropdown li a[href='#{new_user_session_path}']", text: "Sign In"
    assert_select "ul#account_dropdown li a[href='#{new_user_registration_path}']", text: "Sign Up"
  end

  test "signed-in homepage renders the notification sidebar" do
    sign_in users(:leika)

    get root_path

    assert_response :success
    assert_select "li#notifications_panel"
    assert_select "li#notifications_panel[data-action*='mouseenter->notification-dropdown#enter'][data-action*='mouseleave->notification-dropdown#leave']"
    assert_select "button.notification-trigger[aria-expanded='false']"
    assert_select "button.nav-account-trigger[aria-label='Account'][aria-expanded='false'] img.account-icon"
    assert_select "ul#account_dropdown[hidden] li a", count: 2
    assert_select "ul#nav_menu_dropdown li a[href='#{dashboard_path}']", text: "My Log"
    assert_select "ul#nav_menu_dropdown li a[href='#{reviews_path}']", text: "Reviews"
    assert_select "ul#nav_menu_dropdown li a[href='#{reading_sessions_path}']", text: "History"
    assert_select "ul#account_dropdown li a[href='#{edit_user_registration_path}']", text: "Settings"
    assert_select "ul#account_dropdown li a[href='#{destroy_user_session_path}']", text: "Log Out"
  end

  test "admin account menu includes the management workspace" do
    sign_in users(:admin)

    get root_path

    assert_response :success
    assert_select "ul#account_dropdown li a[href='#{admin_root_path}']", text: "Manage", count: 1
    assert_select "li.account-dropdown-divider", count: 1
  end

  test "reset button appears when a genre filter is active" do
    get root_path, params: { genre: "Fiction" }
    assert_response :success
    assert_select "a.genre-pill[href='#{root_path}']", text: "Reset"
  end

  test "reset button is hidden when no genre filter is active" do
    get root_path
    assert_response :success
    assert_select "a.genre-pill-reset", false
  end

  test "most read shows empty state when no books match selected genre" do
    get root_path, params: { genre: "Poetry" }
    assert_response :success
    assert_select "p.empty-state", "No books found for this genre."
  end

  test "home page renders resized cover variant when attached" do
    book = Book.create!(title: "Cover Test Book", author: "Author", total_pages: 100)
    book.cover_image.attach(fixture_file_upload("cover_test.jpg", "image/jpeg"))

    get root_path

    assert_response :success
    assert_select "img.book-cover"
  end

  private

  def assert_trending_query_count(expected)
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      queries.push(payload.fetch(:sql)) if payload.fetch(:sql).include?("AS trending_score")
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    assert_equal expected, queries.length, "Unexpected number of ranking queries: #{queries.inspect}"
  end
end
