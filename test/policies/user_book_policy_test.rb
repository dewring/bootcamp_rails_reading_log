require "test_helper"

class UserBookPolicyTest < ActiveSupport::TestCase
  test "logged-in user can view their log index" do
    assert UserBookPolicy.new(users(:leika), UserBook).index?
  end

  test "guest cannot view log index" do
    refute UserBookPolicy.new(nil, UserBook).index?
  end

  test "user can create a new log entry for their own account" do
    user_book = UserBook.new(user: users(:jaina), book: books(:refactoring))

    assert UserBookPolicy.new(users(:jaina), user_book).create?
  end

  test "user cannot create a duplicate log entry" do
    user_book = UserBook.new(user: users(:leika), book: books(:refactoring))

    refute UserBookPolicy.new(users(:leika), user_book).create?
  end

  test "owner can update and destroy a log entry" do
    policy = UserBookPolicy.new(users(:leika), user_books(:leika_refactoring))

    assert policy.update?
    assert policy.destroy?
  end

  test "non-owner cannot update a log entry" do
    refute UserBookPolicy.new(users(:jaina), user_books(:leika_refactoring)).update?
  end

  test "scope only includes current user's log entries" do
    resolved = UserBookPolicy::Scope.new(users(:leika), UserBook.all).resolve

    assert_equal users(:leika).user_books.ids.sort, resolved.ids.sort
  end
end
