require "test_helper"

class ReviewPolicyTest < ActiveSupport::TestCase
  test "anyone can view reviews" do
    assert ReviewPolicy.new(nil, reviews(:review1)).show?
  end

  test "user can create their first review for a book" do
    review = Review.new(user: users(:jaina), book: books(:refactoring))

    assert ReviewPolicy.new(users(:jaina), review).create?
  end

  test "user cannot create a second review for the same book" do
    review = Review.new(user: users(:leika), book: books(:refactoring))

    refute ReviewPolicy.new(users(:leika), review).create?
  end

  test "owner can update a review" do
    assert ReviewPolicy.new(users(:leika), reviews(:review1)).update?
  end

  test "non-owner cannot update a review" do
    refute ReviewPolicy.new(users(:jaina), reviews(:review1)).update?
  end

  test "scope includes all reviews" do
    resolved = ReviewPolicy::Scope.new(nil, Review.all).resolve

    assert_equal Review.count, resolved.count
  end
end
