require "test_helper"
class BookPolicyTest < ActiveSupport::TestCase
  # index? — 누구나 볼 수 있어요 | anyone can see
  test "anyone can view book index" do
    assert BookPolicy.new(nil, books(:refactoring)).index?
  end

  test "anyone can view a book" do
    assert BookPolicy.new(nil, books(:refactoring)).show?
  end

  test "logged-in user can discover books" do
    assert BookPolicy.new(users(:leika), Book).discover?
  end

  test "guest cannot discover books" do
    refute BookPolicy.new(nil, Book).discover?
  end

  test "logged-in user can request most recent session" do
    assert BookPolicy.new(users(:leika), books(:refactoring)).most_recent_session?
  end

  test "guest cannot request most recent session" do
    refute BookPolicy.new(nil, books(:refactoring)).most_recent_session?
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
