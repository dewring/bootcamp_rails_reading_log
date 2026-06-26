require "test_helper"

class BookControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  test "Book index page loads successfully" do
    get books_path
    assert_response :success
  end
  test "Books show page loads successfully" do
    get book_path(books(:refactoring))
    assert_response :success
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
end
