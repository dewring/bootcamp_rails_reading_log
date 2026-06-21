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
    get most_recent_session_book_path(books(:refactoring))
    assert_redirected_to dashboard_path
  end

  test "most_recent_session redirects back to book when no sessions exist" do
    get most_recent_session_book_path(books(:pragmatic))
    assert_redirected_to book_path(books(:pragmatic)), alert: "No reading sessions yet."
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
end
