require "test_helper"
class ReviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "reviews index shows only the signed-in user's reviews" do
    sign_in users(:leika)

    get reviews_path

    assert_response :success
    assert_select ".reviews-page"
    assert_select "main[aria-label='My Reviews']"
    assert_select "a.my-log-navigation-item--active[href='#{reviews_path}']", text: "Reviews"
    assert_select ".reviews-section-heading h2", text: "Reviews"
    assert_select ".reviews-section-label", text: "Written reviews"
    assert_select ".reviews-card", count: 1
    assert_select ".reviews-card", text: /Great book/
    assert_select ".reviews-card", text: /Loved it/, count: 0
    assert_select ".reviews-position", count: 0
    assert_select ".reviews-card-action--view[href='#{book_path(books(:refactoring))}']", count: 1
    assert_select ".reviews-card-action--edit[data-action='click->review-composer#open']", text: "Edit review", count: 1
    assert_select ".reviews-card-composer[hidden]"
  end

  test "user can update a review from the reviews page and return to it" do
    sign_in users(:leika)

    patch book_review_path(books(:refactoring), reviews(:review1)),
      params: { from: "reviews", review: { rating: 5, body: "Updated from reviews" } }

    assert_redirected_to reviews_path
    assert_equal "Updated from reviews", reviews(:review1).reload.body
  end

  test "reviews index paginates reviews in six-card pages" do
    sign_in users(:leika)

    6.times do |index|
      book = Book.create!(title: "Review book #{index}", author: "Author #{index}", total_pages: 100)
      Review.create!(user: users(:leika), book: book, rating: 4, body: "Review #{index}")
    end

    get reviews_path

    assert_response :success
    assert_select ".reviews-card", count: 6
    assert_select ".reviews-position", count: 0
    assert_select "nav.pagy.series-nav"
  end

  test "guest cannot post any review" do
    get new_book_review_path(books(:refactoring))
    assert_redirected_to new_user_session_path
  end
  test "user create review" do
    sign_in users(:admin)
    post book_reviews_path(books(:refactoring)), params: { review: { rating: 4, body: "Great!" } }
    assert_redirected_to book_path(books(:refactoring))
  end
  test "a Turbo review submission redirects to the full HTML book page with the confirmation" do
    sign_in users(:admin)
    turbo_form_headers = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    post book_reviews_path(books(:refactoring)),
         params: { review: { rating: 4, body: "Great!" } },
         headers: turbo_form_headers
    assert_redirected_to book_path(books(:refactoring))
    follow_redirect!(headers: turbo_form_headers)

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select ".flash-notification", text: /Review added!/
    assert_select ".book-detail-review-card p", text: "Great!"
  end

  test "a review without a rating is not saved and the form shows why" do
    sign_in users(:admin)

    assert_no_difference "Review.count" do
      post book_reviews_path(books(:refactoring)), params: { review: { body: "No stars" } }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: "Rating must be selected (0 to 5 stars)"
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

  test "reviews page shows a designed empty state with a catalog link when the reader has no reviews" do
    sign_in users(:admin)

    get reviews_path

    assert_response :success
    assert_select ".reviews-card", count: 0
    assert_select ".empty-state.empty-state--panel" do
      assert_select "h3.empty-state-title", text: "No reviews yet"
      assert_select "a.empty-state-action[href='#{books_path}']", text: "Browse the catalog"
    end
  end
end
