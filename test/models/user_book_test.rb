require "test_helper"

class UserBookTest < ActiveSupport::TestCase
  def setup
    @user_book = UserBook.new(
      user: users(:jaina),
      book: books(:refactoring),
      status: "reading"
    )
  end

  test "valid user_book is valid" do
    assert @user_book.valid?
  end

  test "status must be valid" do
    @user_book.status = "invalid_status"
    assert_not @user_book.valid?
  end

  test "user cannot add the same book twice" do
    @user_book.user = users(:leika)
    @user_book.book = books(:refactoring)
    assert_not @user_book.valid?
  end

  test "user role must be user or admin" do
    users(:leika).role = "superuser"
    assert_not users(:leika).valid?
  end

  test "admin? returns true for admin user" do
    assert users(:admin).admin?
  end

  test "admin? returns false for regular user" do
    assert_not users(:leika).admin?
  end
end
