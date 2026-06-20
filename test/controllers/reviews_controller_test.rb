require "test_helper"
class ReviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest cannot post any review" do
    get new_book_review_path(books(:refactoring))
    assert_redirected_to new_user_session_path
  end
  test "user create review" do
    sign_in users(:admin)
    post book_reviews_path(books(:refactoring)), params: { review: { rating: 4, body: "Great!" } }
    assert_redirected_to book_path(books(:refactoring))
  end
  test "user cannot review twice to same book" do
    sign_in users(:leika)
    post book_reviews_path(books(:refactoring)), params: { review: { rating: 4, body: "Great!" } }
    assert_redirected_to book_path(books(:refactoring))
  end
  test "user update review" do
    sign_in users(:leika)
    patch book_review_path(books(:refactoring), reviews(:review1)), params: { review: { rating: 5, body: "Updated!" } }
    assert_redirected_to book_path(books(:refactoring))
  end
end
