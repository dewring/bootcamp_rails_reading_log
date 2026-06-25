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

  test "user cannot edit another user's review" do
    sign_in users(:jaina)

    get edit_book_review_path(books(:refactoring), reviews(:review1))

    assert_redirected_to root_path
  end

  test "user cannot update another user's review" do
    sign_in users(:jaina)
    review = reviews(:review1)
    previous_body = review.body

    patch book_review_path(books(:refactoring), review), params: { review: { rating: 5, body: "Changed!" } }

    assert_redirected_to root_path
    assert_equal previous_body, review.reload.body
  end
end
