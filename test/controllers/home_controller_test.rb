require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "anonymous homepage loads eight trending books ordered by score and recency with shared ranks" do
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
      assert_equal [ 2, 1, 1, 1, 1, 1, 1, 1 ], assigns(:trending_books).map(&:trending_score)
      assert_equal [ 1, 2, 2, 2, 2, 2, 2, 2 ], assigns(:trending_books).map(&:trending_rank)
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

  test "a new homepage request recalculates the trending cutoff and candidates" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    Reaction.create!(book: books(:refactoring), user: users(:leika), kind: "like", updated_at: as_of - 7.days)

    travel_to(as_of) do
      get root_path
      assert_equal [ books(:refactoring).id ], assigns(:trending_books).map(&:id)
    end

    travel_to(as_of + 1.second) do
      get root_path
      assert_empty assigns(:trending_books)
    end
  end

  test "trending precedes the other shelves and shows only the existing book card content" do
    book = books(:refactoring)
    Reaction.create!(book: book, user: users(:leika), kind: "dislike", updated_at: 1.hour.ago)

    [ nil, users(:jaina) ].each do |viewer|
      sign_in viewer if viewer
      get root_path

      assert_response :success
      assert_select "section.home-section > header > h2" do |headings|
        assert_equal [ "Trending", "Most Read", "New Books" ], headings.map(&:text)
      end
      assert_select ".home-trending .book-row > a.book-card[href='#{book_path(book)}']", count: 1
      assert_select ".home-trending .book-title", text: book.title
      assert_select ".home-trending .book-author", text: book.author
      assert_select ".home-trending > p, .home-trending time, .home-trending .reaction-panel, .home-trending turbo-cable-stream-source, .home-trending .home-view-all", count: 0
      assert_select ".home-trending .book-row > :not(a.book-card)", count: 0
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
end
