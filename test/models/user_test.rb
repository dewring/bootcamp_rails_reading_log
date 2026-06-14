require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @user = User.new(
      first_name: "Test",
      last_name: "User",
      email: "test@example.com",
      nickname: "testuser",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "valid user is valid" do
    assert @user.valid?
  end

  test "first_name is required" do
    @user.first_name = ""
    assert_not @user.valid?
  end

  test "last_name is required" do
    @user.last_name = ""
    assert_not @user.valid?
  end

  test "nickname is required" do
    @user.nickname = ""
    assert_not @user.valid?
  end

  test "nickname must be unique" do
    @user.nickname = users(:leika).nickname
    assert_not @user.valid?
  end

  test "email must be unique" do
    @user.email = users(:leika).email
    assert_not @user.valid?
  end

  test "password must be at least 8 characters" do
    @user.password = "short"
    @user.password_confirmation = "short"
    assert_not @user.valid?
  end
end
