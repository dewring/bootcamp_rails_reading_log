require "test_helper"
class BookPolicyTest < ActiveSupport::TestCase
  # index? — 누구나 볼 수 있어요 | anyone can see
  test "anyone can view book index" do
    assert BookPolicy.new(users(:leika), books(:refactoring)).index?
  end

  # create? — admin만 | admin only
  test "admin can create a book" do
    assert BookPolicy.new(users(:admin), books(:refactoring)).create?
  end

  test "regular user cannot create a book" do
    refute BookPolicy.new(users(:leika), books(:refactoring)).create?
  end

  # destroy? — admin만 | admin only
  test "admin can destroy a book" do
    assert BookPolicy.new(users(:admin), books(:refactoring)).destroy?
  end

  test "regular user cannot destroy a book" do
    refute BookPolicy.new(users(:leika), books(:refactoring)).destroy?
  end
end
