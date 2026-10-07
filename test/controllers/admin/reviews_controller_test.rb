require "test_helper"

class Admin::ReviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guests and regular readers cannot access or delete community reviews" do
    review = reviews(:review2)
    get admin_reviews_path
    assert_redirected_to new_user_session_path
    assert_no_difference("Review.count") { delete admin_review_path(review) }
    assert_redirected_to new_user_session_path

    sign_in users(:leika)
    get admin_reviews_path
    assert_redirected_to root_path
    assert_no_difference("Review.count") { delete admin_review_path(review) }
    assert_redirected_to root_path
  end

  test "admin sees all readers and the selected full review without invented status controls" do
    sign_in users(:admin)
    review = reviews(:review1)
    review.update!(body: "First paragraph\n\nSecond paragraph <script>alert('unsafe')</script>")

    get admin_reviews_path, params: { review_id: review.id }

    assert_response :success
    assert_select "h1", text: "Review Management"
    assert_select ".admin-review-record", count: 2
    assert_select ".admin-review-select strong", text: users(:leika).nickname
    assert_select ".admin-review-select strong", text: users(:jaina).nickname
    assert_select ".admin-review-body-field dd", text: /Second paragraph <script>/
    assert_select ".admin-review-body-field script", count: 0
    assert_select ".admin-review-field-grid dt", text: "Status", count: 0
    assert_select ".admin-sidebar-nav .is-active[aria-current='page']", text: "Reviews"
    assert_select ".admin-review-detail a[href='#{book_path(review.book)}']", count: 2
  end

  test "search matches nickname title author and phrases without case sensitivity" do
    sign_in users(:admin)
    review = reviews(:review1)
    review.update!(body: "A thoughtful story about finding your way home.")

    [ "MARTITA", "refactoring", "martin fowler", "finding your way home" ].each do |query|
      get admin_reviews_path, params: { q: "  #{query}  " }

      assert_response :success
      assert_select ".admin-review-record", count: 1
      assert_select "#admin_review_#{review.id}.is-selected"
      assert_select ".admin-reviews-search input[name='q'][value='#{query}']"
    end
  end

  test "search treats wildcard characters literally and handles blank and empty results" do
    sign_in users(:admin)
    reviews(:review1).update!(body: "100% worth_it")
    get admin_reviews_path, params: { q: "%" }
    assert_select ".admin-review-record", count: 1
    get admin_reviews_path, params: { q: "_" }
    assert_select ".admin-review-record", count: 1
    get admin_reviews_path, params: { q: "   " }
    assert_select ".admin-review-record", count: 2
    get admin_reviews_path, params: { q: "no such phrase" }
    assert_select ".admin-review-record", count: 0
    assert_select ".admin-reviews-empty h2", text: "No matching reviews"
    assert_select ".admin-review-detail-empty"
  end

  test "rating filter combines with search and excludes a selection outside the results" do
    sign_in users(:admin)
    get admin_reviews_path, params: { q: "book", rating: "1", review_id: reviews(:review2).id }
    assert_response :success
    assert_select ".admin-review-record", count: 1
    assert_select "#admin_review_#{reviews(:review1).id}.is-selected"
    assert_select ".admin-reviews-search input[name='rating'][value='1']"
    assert_select "select[name='rating'] option[selected][value='1']"
    get admin_reviews_path, params: { rating: "invalid" }
    assert_select ".admin-review-record", count: 2
  end

  test "pagination and selected record links retain search and rating" do
    sign_in users(:admin)
    5.times do |index|
      book = Book.create!(title: "Search pagination #{index}", author: "Writer")
      Review.create!(user: users(:leika), book: book, rating: 3, body: "Searchable review")
    end
    get admin_reviews_path, params: { q: "Searchable", rating: "3" }
    assert_select ".admin-review-record", count: 4
    assert_select ".admin-reviews-pagination a[href*='page=2'][href*='q=Searchable'][href*='rating=3']"
    assert_select ".admin-review-select[href*='q=Searchable'][href*='rating=3']", count: 4
    get admin_reviews_path, params: { q: "Searchable", rating: "3", page: 2 }
    assert_select ".admin-review-record", count: 1
  end

  test "admin can delete another readers review and keep filters" do
    sign_in users(:admin)
    review = reviews(:review2)
    assert_difference("Review.count", -1) do
      delete admin_review_path(review), params: { q: "Loved", rating: "4" }
    end
    assert_redirected_to admin_reviews_path(q: "Loved", rating: "4")
    assert_nil Review.find_by(id: review.id)
    assert Review.exists?(reviews(:review1).id)
  end
end
