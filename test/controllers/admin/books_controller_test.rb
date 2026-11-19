require "test_helper"

class Admin::BooksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
  end

  test "catalog keeps the shared shell and renders selectable cards and metadata" do
    book = books(:refactoring)
    book.book_editions.create!(ol_edition_key: "/books/OLCATALOGM", isbn: "9780134757599", language: "English")

    get admin_catalog_path, params: { book_id: book.id }

    assert_response :success
    assert_select ".admin-topbar .nav-logo-icon img[src*='book-open']"
    assert_select ".admin-sidebar-nav .admin-sidebar-icon--library"
    assert_select ".admin-sidebar-link.is-active[aria-current='page']", text: "Catalog"
    assert_select ".admin-catalog-record.is-selected a[aria-current='true']", text: /Refactoring/
    assert_select ".admin-catalog-record-meta", text: "Fiction · English · 448p"
    assert_select "a[aria-label='Edit Refactoring']", count: 1
    assert_select "button[aria-label='Delete Refactoring']", text: "Delete"
    assert_select "input#book_title[value='Refactoring']"
    assert_select "input#catalog_isbn[readonly][value='9780134757599']"
    assert_select "input#catalog_metadata[readonly][value='Fiction · English · 448p']"
    assert_select "input#catalog_status", count: 0
    assert_select "details.admin-catalog-extra-metadata:not([open])"
    assert_select "input#book_total_pages[value='448']"
    assert_select "input#book_cover_image[type='file']"
    assert_select "input[value='Fiction'][checked]"
    assert_select "input[type='submit'][value='Save changes']"
  end

  test "genre dropdown preserves search and all records clears only the genre" do
    get admin_catalog_path, params: { genre: "Fiction", q: "Refactoring" }

    assert_response :success
    assert_select ".admin-catalog-record", count: 1
    assert_select ".admin-catalog-search input[name='genre'][value='Fiction']"
    assert_select ".admin-catalog-genre-filter button[aria-expanded='false'][aria-controls='admin-catalog-genre-menu']", text: "Fiction"
    assert_select "nav#admin-catalog-genre-menu[hidden] a", count: Genre::GENRES.size
    assert_select "nav#admin-catalog-genre-menu a[aria-current='true']", text: "Fiction"
    assert_select "nav#admin-catalog-genre-menu a" do |links|
      links.each do |link|
        query = Rack::Utils.parse_query(URI.parse(link["href"]).query)
        assert_equal "Refactoring", query["q"]
        assert_equal link.text, query["genre"]
        assert_nil query["page"]
      end
    end
    assert_select "a.admin-catalog-filter", text: "All records" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "Refactoring", query["q"]
      assert_nil query["genre"]
    end
    assert_select ".admin-catalog-filters button", text: /Status/, count: 0
  end

  test "record actions and page links preserve the catalog query, sort, and direction" do
    genre = genres(:fiction)
    12.times { |number| Book.create!(title: "Catalog #{format('%02d', number)}", author: "Catalog Author", genres: [ genre ]) }

    get admin_catalog_path, params: { q: "Catalog", genre: "Fiction", sort: "title", direction: "desc", page: 1 }

    assert_select ".admin-catalog-record", count: 10
    assert_select "a[aria-label^='Edit Catalog']" do |links|
      links.each do |link|
        query = Rack::Utils.parse_query(URI.parse(link["href"]).query)
        assert_equal "Catalog", query["q"]
        assert_equal "Fiction", query["genre"]
        assert_equal "desc", query["direction"]
        assert_equal "1", query["page"]
      end
    end
    assert_select ".admin-catalog-list-footer nav.pagy a[href*='page=2']", minimum: 1 do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "Catalog", query["q"]
      assert_equal "Fiction", query["genre"]
      assert_equal "title", query["sort"]
      assert_equal "desc", query["direction"]
    end
    assert_select "a.admin-catalog-load-more", count: 0
  end

  test "catalog sort options order books by title or author in either direction" do
    Book.create!(title: "Aardvark Tales", author: "Zed Writer")
    Book.create!(title: "Zebra Tales", author: "Abby Writer")

    {
      { sort: "title", direction: "asc" } => [ { title: :asc, id: :asc }, "Title · A–Z" ],
      { sort: "title", direction: "desc" } => [ { title: :desc, id: :desc }, "Title · Z–A" ],
      { sort: "author", direction: "asc" } => [ { author: :asc, title: :asc, id: :asc }, "Author · A–Z" ],
      { sort: "author", direction: "desc" } => [ { author: :desc, title: :desc, id: :desc }, "Author · Z–A" ]
    }.each do |options, (expected_order, label)|
      get admin_catalog_path, params: options

      assert_response :success
      assert_equal Book.reorder(expected_order).limit(10).pluck(:id), assigns(:books).map(&:id), "#{label} returned the wrong order"
      assert_select "button[aria-controls='admin-catalog-sort-menu']", text: label
    end
  end

  test "genre filtering retains every genre in the selected edit form" do
    book = books(:refactoring)
    book.genres.push(Genre.find_or_create_by!(name: "Mystery"))

    get admin_catalog_path, params: { q: "Refactoring", genre: "Fiction" }

    assert_response :success
    assert_select "input[value='Fiction'][checked]"
    assert_select "input[value='Mystery'][checked]"
    metadata = css_select("input#catalog_metadata").first["value"]
    assert_includes metadata, "Fiction"
    assert_includes metadata, "Mystery"
  end

  test "books without edition metadata render truthful fallbacks" do
    book = Book.create!(title: "No Metadata", author: "An Author")

    get admin_catalog_path, params: { book_id: book.id }

    assert_response :success
    assert_select "input#catalog_isbn[value='Not available']"
    assert_select "input#catalog_metadata[value='Genre not set · Language not set · Pages not set']"
    assert_select "input#catalog_status", count: 0
  end

  test "new record opens additional metadata and validation errors preserve editing" do
    get admin_catalog_path, params: { new_book: true }

    assert_response :success
    assert_select "details.admin-catalog-extra-metadata[open]"
    assert_select "input#catalog_status", count: 0
    assert_select "input[type='submit'][value='Add book']"
    assert_select ".admin-catalog-extra-metadata + .admin-catalog-form-actions", count: 1

    post admin_books_path, params: { book: { title: "", author: "An Author" } }

    assert_response :unprocessable_entity
    assert_select ".admin-validation-errors[role='alert']", text: /Title can't be blank/
    assert_select "input#book_author[value='An Author']"
    assert_select "details.admin-catalog-extra-metadata[open]"
  end

  test "updating the compact form retains selected genres" do
    book = books(:refactoring)

    patch admin_book_path(book), params: { book: { title: "Updated Title", author: book.author, total_pages: 500, genre_names: [ "Fiction" ] } }

    assert_redirected_to admin_catalog_path(book_id: book.id)
    assert_equal "Updated Title", book.reload.title
    assert_equal 500, book.total_pages
    assert_equal [ "Fiction" ], book.genres.pluck(:name)
  end

  test "new record submission still accepts a cover and additional metadata" do
    assert_difference "Book.count", 1 do
      post admin_books_path, params: {
        book: {
          title: "Complete Catalog Record", author: "An Author", total_pages: 250,
          genre_names: [ "Fiction", "Mystery" ],
          cover_image: fixture_file_upload("cover_test.jpg", "image/jpeg")
        }
      }
    end

    book = Book.find_by!(title: "Complete Catalog Record")
    assert_redirected_to admin_catalog_path(book_id: book.id)
    assert_equal 250, book.total_pages
    assert_equal [ "Fiction", "Mystery" ], book.genres.order(:name).pluck(:name)
    assert book.cover_image.attached?
  end

  test "delete action removes the selected record and returns to the catalog" do
    book = Book.create!(title: "Disposable Catalog Test", author: "An Author")

    assert_difference "Book.count", -1 do
      delete admin_book_path(book)
    end

    assert_redirected_to admin_catalog_path
    assert_not Book.exists?(book.id)
  end

  test "catalog remains restricted to administrators" do
    sign_out users(:admin)
    get admin_catalog_path
    assert_redirected_to new_user_session_path

    sign_in users(:leika)
    get admin_catalog_path
    assert_redirected_to root_path
  end
end
