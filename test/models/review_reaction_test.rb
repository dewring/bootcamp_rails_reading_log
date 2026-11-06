require "test_helper"
require_relative "../support/reaction_model_tests"

class ReviewReactionTest < ActiveSupport::TestCase
  include ReactionModelTests

  setup do
    @target = Review.create!(user: users(:admin), book: books(:refactoring), rating: 4, body: "A reflection")
  end

  private

  def reaction_model
    ReviewReaction
  end

  def reaction_target
    @target
  end

  def target_foreign_key
    :review_id
  end
end
