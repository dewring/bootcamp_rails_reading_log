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
    assert_select ".admin-reviews-rating-filter button[aria-expanded='false'][aria-controls='admin-reviews-rating-menu']", text: "1 / 5 stars"
    assert_select "nav#admin-reviews-rating-menu[hidden] a", count: 7
    assert_select "nav#admin-reviews-rating-menu a[aria-current='true']", text: "1 / 5 stars"
    assert_select "nav#admin-reviews-rating-menu a" do |links|
      links.each_with_index do |link, index|
        query = Rack::Utils.parse_query(URI.parse(link["href"]).query)
        assert_equal "book", query["q"]
        if index.zero?
          assert_nil query["rating"]
        else
          assert_equal (index - 1).to_s, query["rating"]
        end
        assert_nil query["page"]
        assert_nil query["review_id"]
      end
    end
    assert_select "a.admin-reviews-filter", text: "All records" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "book", query["q"]
      assert_nil query["rating"]
    end
    get admin_reviews_path, params: { rating: "invalid" }
    assert_select ".admin-review-record", count: 2
    assert_select "nav#admin-reviews-rating-menu a[aria-current='true']", text: "All ratings"
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

  test "the fifth review enables shared Pagy navigation with four records per page" do
    sign_in users(:admin)
    get admin_reviews_path
    assert_select ".admin-reviews-pagination .pagy.series-nav", count: 0

    3.times do |index|
      book = Book.create!(title: "Pagination boundary #{index}", author: "Writer")
      Review.create!(user: users(:leika), book: book, rating: 3, body: "Fifth review boundary")
    end
    assert_equal 5, Review.count

    get admin_reviews_path
    assert_select ".admin-review-record", count: 4
    assert_select ".admin-reviews-pagination .pagy.series-nav" do
      assert_select "a[aria-current='page']", text: "1"
      assert_select "a[href*='page=2']", text: "2"
    end
    assert_select ".admin-reviews-pagination p", text: "5 reviews · Page 1 of 2"

    get admin_reviews_path, params: { page: 2 }
    assert_select ".admin-review-record", count: 1
    assert_select ".admin-reviews-pagination .pagy.series-nav a[aria-current='page']", text: "2"
    assert_select ".admin-reviews-pagination p", text: "5 reviews · Page 2 of 2"
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
