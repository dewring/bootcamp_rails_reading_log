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
      assert_equal as_of, assigns(:trending_as_of)
      assert_equal [ candidates.last.id, *candidates.first(7).map(&:id) ], assigns(:trending_books).map(&:id)
      assert_equal [ 2, 1, 1, 1, 1, 1, 1, 1 ], assigns(:trending_books).map(&:trending_score)
      assert_equal [ 1, 2, 2, 2, 2, 2, 2, 2 ], assigns(:trending_books).map(&:trending_rank)
    end
  end

  test "trending totals include old reactions but exclude inactive accounts" do
    as_of = Time.zone.local(2026, 11, 9, 12)
    book = books(:refactoring)
    Reaction.create!(book: book, user: users(:leika), kind: "dislike", updated_at: as_of - 1.day)
    Reaction.create!(book: book, user: users(:jaina), kind: "love", updated_at: as_of - 10.days)
    Reaction.create!(book: book, user: users(:admin), kind: "wow", updated_at: as_of - 1.day)
    users(:admin).update!(account_status: "suspended")

    travel_to(as_of) do
      get root_path

      assert_response :success
      assert_equal [ 1 ], assigns(:trending_books).map(&:trending_score)
      assert_equal({ [ book.id, "dislike" ] => 1, [ book.id, "love" ] => 1 }, assigns(:trending_reaction_counts))
      assert_equal ReactionType.order(:id).pluck(:key), assigns(:trending_reaction_types).map(&:key)
    end
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
      assert_equal as_of + 1.second, assigns(:trending_as_of)
      assert_empty assigns(:trending_books)
      assert_empty assigns(:trending_reaction_counts)
    end
  end

  test "homepage loads successfully" do
    get root_path

    assert_response :success
    assert_select "section.home-hero[aria-labelledby='home-hero-title']"
    assert_select "h1#home-hero-title", "Summer Reading Challenge — Join Now"
    assert_select "section.home-section", count: 2
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
