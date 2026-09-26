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

  test "provides notification panel locals for the user" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    notification = BookClubPickNotifier.with(
      record: book_club,
      book_club_name: book_club.name,
      book_title: "The Left Hand of Darkness"
    ).deliver(users(:leika), enqueue_job: false).notifications.first

    locals = users(:leika).notification_panel_locals

    assert_equal 1, locals[:unread_count]
    assert_includes locals[:notifications], notification
  end
end
