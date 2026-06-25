require "test_helper"

class BookGenrePolicyTest < ActiveSupport::TestCase
  test "anyone can view book genre assignments" do
    assert BookGenrePolicy.new(nil, book_genres(:some_name1)).show?
  end

  test "admin can manage book genre assignments" do
    policy = BookGenrePolicy.new(users(:admin), book_genres(:some_name1))

    assert policy.create?
    assert policy.update?
    assert policy.destroy?
  end

  test "regular user cannot manage book genre assignments" do
    refute BookGenrePolicy.new(users(:leika), book_genres(:some_name1)).create?
  end
end
