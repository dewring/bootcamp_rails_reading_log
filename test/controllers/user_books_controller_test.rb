require "test_helper"
class UserBooksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest cannot access user log" do
    get new_user_book_path(book_id: books(:refactoring))
    assert_redirected_to new_user_session_path
  end
  test "admin can add a book to their log" do
    sign_in users(:admin)
    post user_books_path, params: { user_book: { book_id: books(:pragmatic).id, status: "reading" } }
    assert_redirected_to dashboard_path
  end

  test "user create book log" do
    sign_in users(:jaina)
    post user_books_path, params: { user_book: { book_id: books(:refactoring).id, status: "reading" } }
    assert_redirected_to dashboard_path
  end
  test "user update book log" do
    sign_in users(:leika)
    patch user_book_path(user_books(:leika_refactoring)), params: { user_book: { status: "completed" } }
    assert_redirected_to dashboard_path
  end

  test "user cannot update another user's book log" do
    sign_in users(:jaina)
    user_book = user_books(:leika_refactoring)
    previous_status = user_book.status

    patch user_book_path(user_book), params: { user_book: { status: "finished" } }

    assert_redirected_to root_path
    assert_equal previous_status, user_book.reload.status
  end

  test "user destroy book log" do
    sign_in users(:leika)
    delete user_book_path(user_books(:leika_refactoring))
    assert_redirected_to dashboard_path
  end

  test "user cannot destroy another user's book log" do
    sign_in users(:jaina)

    assert_no_difference "UserBook.count" do
      delete user_book_path(user_books(:leika_refactoring))
    end

    assert_redirected_to root_path
  end
end
