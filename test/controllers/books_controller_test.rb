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
  test "guest cannot access new book" do
    get new_book_path
    assert_redirected_to new_user_session_path
  end

  test "regular user cannot access new book" do
    sign_in users(:leika)
    get new_book_path
    assert_redirected_to root_path
  end
  test "admin can create a book" do
    sign_in users(:admin)
    post books_path, params: { book: { title: "New Book", author: "Author", total_pages: 100 } }
    assert_redirected_to book_path(Book.last)
  end
  test "admin can not create a book with null title" do
    sign_in users(:admin)
    post books_path, params: { book: { title: "", author: "Author", total_pages: 100 } }
    assert_response :unprocessable_entity
  end

  test "edit form pre-checks genres already assigned to book" do
    sign_in users(:admin)
    get edit_book_path(books(:refactoring))
    assert_response :success
    assert_select "input[type='checkbox'][value='Fiction'][checked='checked']"
  end
end
