require "test_helper"
require_relative "../support/reaction_model_tests"

class ReactionTest < ActiveSupport::TestCase
  include ReactionModelTests

  setup do
    @target = Book.create!(title: "Reaction target", author: "Test author")
  end

  private

  def reaction_model
    Reaction
  end

  def reaction_target
    @target
  end

  def target_foreign_key
    :book_id
  end
end
