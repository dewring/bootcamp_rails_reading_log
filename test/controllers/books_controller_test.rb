require "test_helper"
class BookControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "Book index page loads successfully" do
    get books_path
    assert_response :success
  end
  test "Books show page loads successfully" do
    get book_path(books(:refactoring))
    assert_response :success
    assert_select "main.book-detail-page"
    assert_select "nav.book-detail-breadcrumb"
    assert_select "section.book-detail-hero"
    assert_select "section.book-detail-information"
    assert_select "h2#book-detail-facts-title", text: "Genres & details"
    assert_select "section.book-detail-reviews"
  end

  test "admin book detail edit opens that book in the catalog workspace" do
    sign_in users(:admin)
    book = books(:pragmatic)

    get book_path(book)

    assert_response :success
    assert_select "a.book-detail-button[href='#{admin_catalog_path(book_id: book.id)}']", text: "Edit"
    assert_select "a[href='#{edit_admin_book_path(book)}']", count: 0

    get admin_catalog_path(book_id: book.id)

    assert_response :success
    assert_select "form[action='#{admin_book_path(book)}'] input[name='book[title]'][value='#{book.title}']"
  end

  test "regular reader does not see the admin book edit action" do
    sign_in users(:jaina)

    get book_path(books(:pragmatic))

    assert_response :success
    assert_select ".book-detail-actions a", text: "Edit", count: 0
  end

  test "show page displays a zero rating when there are no reviews" do
    book = Book.create!(title: "Unrated Book", author: "An Author")

    get book_path(book)

    assert_select ".book-detail-rating strong", text: "0.0"
    assert_select ".book-detail-rating", text: /0 community reviews/
  end

  test "signed-in reader sees the empty review state and closed composer" do
    sign_in users(:jaina)
    book = Book.create!(title: "Reviewable Book", author: "An Author")

    get book_path(book)

    assert_response :success
    assert_select "section.book-detail-reviews[data-controller='review-composer']"
    assert_select "img.book-detail-empty-icon", count: 1
    assert_select ".book-detail-review-empty h3", text: "No reviews yet"
    assert_select ".book-detail-review-empty button[data-action='click->review-composer#open']", text: /Write a Review/
    assert_select ".book-detail-review-composer[data-review-composer-target='composer'][hidden]", count: 1
    assert_select "textarea[name='review[body]'][maxlength='2000']", count: 1
    assert_select "input[type='radio'][name='review[rating]'][data-action='change->review-composer#updateRating']", count: 5
    assert_select "label[data-review-composer-target='ratingStar']", count: 5
  end

  test "signed-in reader sees existing reviews and can open the composer" do
    sign_in users(:jaina)

    get book_path(books(:refactoring))

    assert_response :success
    assert_select ".book-detail-review-card", count: 1
    assert_select ".book-detail-review-card", text: /Great book/
    assert_select ".profile-avatar--review .profile-avatar-initials", text: users(:leika).nickname.first(2).upcase
    assert_select ".book-detail-reviewer strong", text: "martita"
    assert_select ".book-detail-reviewer strong", text: /leika/, count: 0
    assert_select ".book-detail-section-heading button[data-action='click->review-composer#open']", text: /Write a Review/
    assert_select ".book-detail-review-composer[data-review-composer-target='composer'][hidden]", count: 1
  end

  test "review owner sees an inline edit composer without an edit-page link" do
    sign_in users(:leika)

    get book_path(books(:refactoring))

    assert_response :success
    assert_select "button.book-detail-button[data-action='click->review-composer#open']", text: /Edit my Review/, count: 1
    assert_select "a[href='#{edit_book_review_path(books(:refactoring), reviews(:review1))}']", count: 0
    assert_select ".book-detail-review-composer h3", text: "Edit a review", count: 1
    assert_select ".book-detail-review-composer form[action='#{book_review_path(books(:refactoring), reviews(:review1))}']", count: 1
    assert_select ".book-detail-review-composer input[name='review[rating]'][value='1'][checked='checked']", count: 1
    assert_select ".book-detail-review-composer textarea[name='review[body]']", text: "Great book", count: 1
    assert_select ".book-detail-review-composer button[type='submit']", text: /Update Review/, count: 1
  end

  test "signed-in reader sees start reading and want to read actions without a saved state" do
    sign_in users(:jaina)

    get book_path(books(:pragmatic))

    assert_select "a.book-detail-button-primary[href='#{book_reading_journal_path(books(:pragmatic))}']", text: /Start Reading/
    assert_select ".book-detail-button-secondary", text: /Want to Read/
    assert_select "form[action='#{user_books_path}'] input[name='user_book[book_id]'][value='#{books(:pragmatic).id}']"
    assert_select "form[action='#{user_books_path}'] input[name='user_book[status]'][value='want_to_read']"
  end

  test "want-to-read state is shown for a saved want-to-read book" do
    sign_in users(:leika)

    get book_path(books(:pragmatic))

    assert_select ".book-detail-state-want", text: /Saved to Want to Read/
    assert_select "a.book-detail-button-primary[href='#{book_reading_journal_path(books(:pragmatic))}']", text: /Start Reading/
  end

  test "a reading session changes a want-to-read book to currently reading" do
    sign_in users(:leika)
    book = books(:pragmatic)
    ReadingSession.create!(user: users(:leika), book: book, read_on: Date.today, pages_read: 10)

    get book_path(book)

    assert_select ".book-detail-state-reading.action-button.action-button--active", text: /Currently Reading/
    assert_select ".book-detail-button-primary", text: /Start Reading/, count: 0
  end

  test "currently-reading state is shown when the reader has a session" do
    sign_in users(:leika)

    get book_path(books(:refactoring))

    assert_select ".book-detail-state-reading.action-button.action-button--active[href='#{dashboard_path}']", text: /Currently Reading/
    assert_select ".book-detail-button-secondary", text: /Most Recent Session/, count: 0
    assert_select ".book-detail-button-secondary", text: /Want to Read/, count: 0
  end

  test "finished books show the currently reading action and open finished history" do
    sign_in users(:leika)
    user_book = users(:leika).user_books.find_by!(book: books(:refactoring))
    user_book.update!(status: "finished")

    get book_path(books(:refactoring))

    assert_select ".book-detail-state-reading.action-button.action-button--active[href='#{book_finished_journal_path(books(:refactoring))}']", text: /Currently Reading/
    assert_select ".book-detail-button-primary", text: /Start Reading/, count: 0
  end

  test "editions with a cover image are listed before editions without one" do
    book = books(:refactoring)
    without_cover = book.book_editions.create!(ol_edition_key: "/books/OL1M")
    with_cover = book.book_editions.create!(ol_edition_key: "/books/OL2M")
    with_cover.cover_image.attach(fixture_file_upload("cover_test.jpg", "image/jpeg"))

    get book_path(book)

    editions = assigns(:book_editions)
    assert_equal with_cover, editions.first
    assert_includes editions, without_cover
  end
  test "most_recent_session redirects to dashboard when sessions exist" do
    sign_in users(:leika)
    get most_recent_session_book_path(books(:refactoring))
    assert_redirected_to dashboard_path
  end

  test "most_recent_session redirects back to book when no sessions exist" do
    sign_in users(:leika)
    get most_recent_session_book_path(books(:pragmatic))
    assert_redirected_to book_path(books(:pragmatic)), alert: "No reading sessions yet."
  end

  test "guest cannot access most recent session" do
    get most_recent_session_book_path(books(:refactoring))
    assert_redirected_to new_user_session_path
  end

  test "discover redirects to a random unread book" do
    sign_in users(:admin)
    get discover_books_path
    assert_response :redirect
    assert_includes response.location, "/books/"

    book_id = response.location.split("/").last.to_i
    assert book_id > 0

    read_ids = users(:admin).books.pluck(:id)
    assert_not read_ids.include?(book_id)
  end

  test "discover redirects to root when all books are read" do
    sign_in users(:leika)
    get discover_books_path
    assert_redirected_to root_path
  end

  test "guest cannot access new book" do
    get new_admin_book_path
    assert_redirected_to new_user_session_path
  end

  test "regular user cannot access new book" do
    sign_in users(:leika)
    get new_admin_book_path
    assert_redirected_to root_path
  end
  test "admin can create a book" do
    sign_in users(:admin)
    post admin_books_path, params: { book: { title: "New Book", author: "Author", total_pages: 100 } }
    assert_redirected_to book_path(Book.last)
  end
  test "admin can not create a book with null title" do
    sign_in users(:admin)
    post admin_books_path, params: { book: { title: "", author: "Author", total_pages: 100 } }
    assert_response :unprocessable_entity
  end

  test "edit form pre-checks genres already assigned to book" do
    sign_in users(:admin)
    get edit_admin_book_path(books(:refactoring))
    assert_response :success
    assert_select "input[type='checkbox'][value='Fiction'][checked='checked']"
  end

  # Default page test
  test "GET /books returns 10 books by default" do
    sign_in users(:leika)

    genre = Genre.find_or_create_by!(name: "Fiction")
    15.times do |i|
      book = Book.create!(title: "Book #{i}", author: "Author #{i}", total_pages: 100)
      BookGenre.create!(book: book, genre: genre)
    end

    get books_path
    assert_response :success
    assert_equal 10, assigns(:books).count
    assert_select ".catalog-results-header p", text: "Showing #{Book.count} books"
  end

  test "catalog result count shows the total filtered result count" do
    sign_in users(:leika)

    genre = Genre.find_or_create_by!(name: "Fiction")
    15.times do |i|
      book = Book.create!(title: "Counted Book #{i}", author: "Author #{i}", total_pages: 100)
      BookGenre.create!(book: book, genre: genre)
    end

    get books_path, params: { genre: "Fiction" }

    assert_response :success
    assert_equal 10, assigns(:books).count
    assert_select ".catalog-results-header p", text: "Showing #{genre.books.count} books"
  end

  test "most read catalog filter orders books by reading session count" do
    sign_in users(:leika)

    most_read_book = Book.create!(title: "Most Read Filter Winner", author: "Author", total_pages: 100)
    less_read_book = Book.create!(title: "Less Read Filter Book", author: "Author", total_pages: 100)
    3.times do
      ReadingSession.create!(user: users(:leika), book: most_read_book, read_on: Date.current, pages_read: 10)
    end
    ReadingSession.create!(user: users(:leika), book: less_read_book, read_on: Date.current, pages_read: 10)

    get books_path, params: { filter: "most_read" }

    assert_response :success
    ordered_ids = assigns(:books).map(&:id)
    assert_operator ordered_ids.index(most_read_book.id), :<, ordered_ids.index(less_read_book.id)
    assert_select ".catalog-dropdown-trigger", text: /Most Read/
    assert_select "#catalog-filter-menu a.catalog-dropdown-option.is-selected[href*='filter=most_read']", text: "Most Read", count: 1
  end

  test "new books catalog filter orders books newest first" do
    sign_in users(:leika)

    older_book = Book.create!(title: "Older New Book", author: "Author", total_pages: 100)
    newer_book = Book.create!(title: "Newer New Book", author: "Author", total_pages: 100)
    older_book.update_columns(created_at: 2.days.ago)
    newer_book.update_columns(created_at: 1.year.from_now)

    get books_path, params: { filter: "new_books" }

    assert_response :success
    assert_equal newer_book.id, assigns(:books).first.id
    assert_select ".catalog-dropdown-trigger", text: /New Books/
    assert_select "#catalog-filter-menu a.catalog-dropdown-option.is-selected[href*='filter=new_books']", text: "New Books", count: 1
  end

  test "catalog sort control exposes the home-style dropdown options" do
    sign_in users(:leika)

    get books_path, params: { q: "Book", genre: "Fiction", sort: "author" }

    assert_response :success
    assert_select ".catalog-sort-form[data-controller='nav-menu']", count: 1
    assert_select "button.catalog-sort-trigger[aria-controls='catalog-sort-menu']", text: /Author/, count: 1
    assert_select "#catalog-sort-menu a.catalog-sort-option.is-selected[href*='sort=author']", text: "Author", count: 1
    assert_select "#catalog-sort-menu a[href*='sort=title'][href*='q=Book'][href*='genre=Fiction']", text: "Title A-Z", count: 1
  end

  test "active genre filter link clears the genre on the next click" do
    sign_in users(:leika)

    get books_path, params: { genre: "Fiction" }

    assert_response :success
    assert_select "a.catalog-genre-option.is-active[href='#{books_path}'][aria-pressed='true']", count: 1
    assert_select "a.catalog-genre-option.is-active .catalog-checkbox-icon", count: 1
    assert_select "a.catalog-genre-option:not(.is-active)[href*='genre=Fantasy']", count: 1
  end

  test "catalog sidebar exposes the Figma find dropdown options" do
    sign_in users(:leika)

    get books_path

    assert_response :success
    assert_select "button.catalog-dropdown-trigger[aria-controls='catalog-find-menu']", count: 1
    assert_select "#catalog-find-menu a[href='#{search_books_path}']", text: "Open Library", count: 1
    assert_select "#catalog-find-menu a[href='#{quick_add_books_path}']", text: "Search ISBN", count: 1
  end

  test "catalog search uses a wide input and a separate search button" do
    sign_in users(:leika)

    get books_path

    assert_response :success
    assert_select ".catalog-search-input img.catalog-search-icon", count: 1
    assert_select ".catalog-search-input input[type='search'][placeholder='Search books by title, author, or keyword...']", count: 1
    assert_select ".catalog-search-form input.catalog-search-submit[type='submit'][value='Search']", count: 1
  end

  test "catalog search width does not change when filters are applied" do
    sign_in users(:leika)

    get books_path, params: { q: "Book", genre: "Fiction" }

    assert_response :success
    assert_select ".catalog-search-form", count: 1
    assert_select ".catalog-active-filters", text: "2 filters active", count: 1
    assert_select ".catalog-active-filters-slot", count: 1
  end

  test "admin catalog sidebar shows the Add Book control and admin badge" do
    sign_in users(:admin)

    get books_path

    assert_response :success
    assert_select "a.catalog-add-book[href='#{new_admin_book_path}']", text: /Add Book/, count: 1
    assert_select ".catalog-admin-badge", text: /Admin Only/, count: 1
  end

  test "catalog cards do not show Add to Log actions" do
    sign_in users(:leika)

    get books_path

    assert_response :success
    assert_select "a[href*='user_books/new']", count: 0
    assert_select ".catalog-sidebar-footer", count: 0
    assert_select "#catalog-filter-menu a[href='#{discover_books_path}']", text: "Discover", count: 1
  end

  test "GET /books?page=2 returns different books than page 1" do
    sign_in users(:leika)

    genre = Genre.find_or_create_by!(name: "Fiction")
    15.times do |i|
      book = Book.create!(title: "Book #{i}", author: "Author #{i}", total_pages: 100)
      BookGenre.create!(book: book, genre: genre)
    end

    get books_path
    page_1_ids = assigns(:books).map(&:id)

    get books_path, params: { page: 2 }
    page_2_ids = assigns(:books).map(&:id)

    assert (page_1_ids & page_2_ids).empty?
  end

  test "search filter is preserved on page 2" do
    sign_in users(:leika)

    genre = Genre.find_or_create_by!(name: "Fiction")
    15.times do |i|
      book = Book.create!(title: "Book #{i}", author: "Author #{i}", total_pages: 100)
      BookGenre.create!(book: book, genre: genre)
    end
    Book.create!(title: "Completely Different", author: "Someone", total_pages: 100)

    get books_path, params: { q: "Book", page: 2 }

    assert_response :success
    assigns(:books).each do |book|
      assert_match "Book", book.title
    end
  end
  test "per_page is capped at the maximum" do
    sign_in users(:leika)

    genre = Genre.find_or_create_by!(name: "Fiction")
    25.times do |i|
      book = Book.create!(title: "Book #{i}", author: "Author #{i}", total_pages: 100)
      BookGenre.create!(book: book, genre: genre)
    end

    get books_path, params: { per_page: 999 }

    assert_response :success
    assert assigns(:books).count <= 20
  end

  test "invalid page param 'abc' falls back to page 1" do
    sign_in users(:leika)
    get books_path, params: { page: "abc" }
    assert_response :success
  end

  test "negative page param falls back to page 1" do
    sign_in users(:leika)
    get books_path, params: { page: -1 }
    assert_response :success
  end
  test "out-of-range page returns redirect to page 1" do
    sign_in users(:leika)
    get books_path, params: { page: 999999 }
    assert_response :success
  end
  test "JSON response includes pagination metadata" do
    sign_in users(:leika)

    genre = Genre.find_or_create_by!(name: "Fiction")
    15.times do |i|
      book = Book.create!(title: "Book #{i}", author: "Author #{i}", total_pages: 100)
      BookGenre.create!(book: book, genre: genre)
    end

    get books_path(format: :json)
    assert_response :success

    data = JSON.parse(response.body)

    assert data["pagination"].present?
    assert_equal 1, data["pagination"]["page"]
  end

  test "GET search redirects when not signed in" do
    get search_books_url
    assert_redirected_to new_user_session_path
  end

  test "GET search returns results for signed-in user" do
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: { q: "Harry Potter", page: 1, limit: 100 })
      .to_return(
        status: 200,
        body: '{"docs": [{"key": "/works/OL82563W", "title": "Harry Potter"}], "numFound": 1000}',
        headers: { "Content-Type" => "application/json" }
      )

    sign_in users(:leika)
    get search_books_url, params: { q: "Harry Potter", page: 1, limit: 10 }
    assert_response :success
  end

  test "GET search page 2 returns different results than page 1" do
    docs = (1..25).map { |i| { "key" => "/works/OL#{i}W", "title" => "Book #{i}" } }
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: { q: "Harry Potter", page: 1, limit: 100 })
      .to_return(
        status: 200,
        body: { docs: docs, numFound: 25 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    sign_in users(:leika)

    get search_books_url, params: { q: "Harry Potter" }
    page_1_keys = assigns(:results).map { |r| r["key"] }

    get search_books_url, params: { q: "Harry Potter", page: 2 }
    page_2_keys = assigns(:results).map { |r| r["key"] }

    assert (page_1_keys & page_2_keys).empty?
  end

  test "POST import redirects when not signed in" do
    post import_books_url, params: { ol_work_key: "/works/OL82563W", title: "Harry Potter", author: "J. K. Rowling" }
    assert_redirected_to new_user_session_path
  end

  test "POST import creates a book and redirects" do
    sign_in users(:leika)
    assert_difference "Book.count", 1 do
      post import_books_url, params: {
        ol_work_key: "/works/OL999W",
        title:       "New Book",
        author:      "Some Author"
      }
    end
    assert_redirected_to book_path(Book.last)
  end

  test "caches edition list on show" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    Rails.cache.clear
    sign_in users(:leika)

    get book_path(books(:refactoring))
    assert_response :success

    cached = Rails.cache.read("book:#{books(:refactoring).id}:editions:list")
    assert_not_nil cached
  end

  test "show page renders resized cover variant when attached" do
    book = books(:refactoring)
    book.cover_image.attach(fixture_file_upload("cover_test.jpg", "image/jpeg"))

    get book_path(book)

    assert_response :success
    assert_select "img.book-detail-cover-image.book-show-image"
  end

  test "invalidates edition cache after mirroring" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    book = Book.create!(
      title: "Test Book",
      author: "Author",
      total_pages: 100,
      ol_work_key: "/works/OL123W"
    )
    Rails.cache.write("book:#{book.id}:editions:list", [ "fake" ])

    stub_request(:get, /openlibrary.org/).to_return(status: 200, body: "{}", headers: {})

    BookMirrorService.new("OL123W").mirror_book

    assert_nil Rails.cache.read("book:#{book.id}:editions:list")
  end

  test "searching by edition title returns the parent book" do
    sign_in users(:leika)
    book = Book.create!(title: "Some Book", author: "Author", total_pages: 100)
    BookEdition.create!(ol_edition_key: "/books/OL001M", book: book, title: "마법사의 돌")

    get books_path, params: { q: "마법사의 돌" }

    assert_response :success
    assert_includes assigns(:books), book
  end

  test "import synchronously attaches the cover from the search result" do
    sign_in users(:leika)
    stub_request(:get, "https://covers.openlibrary.org/b/id/12345-M.jpg")
      .to_return(status: 200, body: file_fixture("cover_test.jpg").read, headers: { "Content-Type" => "image/jpeg" })

    post import_books_url, params: {
      ol_work_key: "/works/OL888W",
      title:       "Cover Book",
      author:      "Some Author",
      cover_i:     "12345"
    }

    book = Book.find_by!(ol_work_key: "/works/OL888W")
    assert book.cover_image.attached?
  end

  test "import skips cover attachment when no cover_i is given" do
    sign_in users(:leika)

    post import_books_url, params: {
      ol_work_key: "/works/OL889W",
      title:       "No Cover Book",
      author:      "Some Author"
    }

    book = Book.find_by!(ol_work_key: "/works/OL889W")
    assert_not book.cover_image.attached?
  end

  test "import enqueues BookMirrorJob" do
    sign_in users(:leika)

    assert_enqueued_with(job: BookMirrorJob) do
      post import_books_url, params: { ol_work_key: "/works/OL82563W", title: "Harry Potter", author: "J. K. Rowling" }
    end
  end

  test "guest cannot quick_add" do
    get quick_add_books_url
    assert_redirected_to new_user_session_path
  end

  test "GET quick_add renders the form" do
    sign_in users(:leika)
    get quick_add_books_url
    assert_response :success
  end

  test "POST quick_add with blank isbn re-renders with an error" do
    sign_in users(:leika)
    post quick_add_books_url, params: { isbn: "" }
    assert_response :unprocessable_entity
    assert_select ".quick-add-error"
  end

  test "POST quick_add redirects to book on local ISBN match" do
    sign_in users(:leika)
    book = Book.create!(title: "Test Book", author: "Author")
    BookEdition.create!(book: book, ol_edition_key: "/books/OL1M", isbn: "9780134757599")

    post quick_add_books_url, params: { isbn: "9780134757599" }

    assert_redirected_to book_path(book)
  end

  test "POST quick_add imports from Open Library on local miss and remote hit" do
    sign_in users(:leika)
    stub_request(:get, "https://openlibrary.org/isbn/9780134757599.json")
      .to_return(
        status: 200,
        body: { title: "Refactoring", works: [ { key: "/works/OL45804W" } ], by_statement: "Martin Fowler" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: { title: "Refactoring", description: "", subjects: [] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: { entries: [ { key: "/books/OL1M", isbn_13: [ "9780134757599" ] } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    post quick_add_books_url, params: { isbn: "9780134757599" }

    assert_redirected_to book_path(Book.last)
  end

  test "POST quick_add reaches not-found state when ISBN is unknown everywhere" do
    sign_in users(:leika)
    stub_request(:get, "https://openlibrary.org/isbn/0000000000.json")
      .to_return(status: 404, body: "")

    assert_no_difference [ "Book.count", "BookEdition.count" ] do
      post quick_add_books_url, params: { isbn: "0000000000" }
    end

    assert_response :unprocessable_entity
    assert_select ".quick-add-not-found"
  end
end
