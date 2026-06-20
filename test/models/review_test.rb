require "test_helper"

class ReviewTest < ActiveSupport::TestCase
  def setup
    @review = Review.new(
      user: users(:admin),
      book: books(:refactoring),
      rating: 3,
      body: "Good book"
    )
  end

  test "You complete review this book" do
    assert @review.valid?
  end
  test "same user cannot review same book twice" do
    duplicate = Review.new(user: users(:leika), book: books(:refactoring), rating: 2)
    assert_not duplicate.valid?
  end
  test "Rating must be between 0 and 5" do
    @review.rating = 6
    assert_not @review.valid?
  end
end
