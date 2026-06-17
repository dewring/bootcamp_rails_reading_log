require "test_helper"

class ReadingSessionTest < ActiveSupport::TestCase
  def setup
    @user = users(:leika)
    @book = books(:refactoring)
    @session = ReadingSession.new(
      user: @user,
      book: @book,
      read_on: Date.today,
      pages_read: 10
    )
  end

  test "valid reading session" do
    assert @session.valid?
  end

  test "invalid without read_on" do
    @session.read_on = nil
    assert_not @session.valid?
  end

  test "invalid without pages_read" do
    @session.pages_read = nil
    assert_not @session.valid?
  end

  test "invalid if pages_read is zero" do
    @session.pages_read = 0
    assert_not @session.valid?
  end

  test "invalid if pages_read is negative" do
    @session.pages_read = -5
    assert_not @session.valid?
  end

  test "notes are optional" do
    @session.notes = nil
    assert @session.valid?
  end

  test "belongs to a user" do
    assert_equal @user, @session.user
  end

  test "belongs to a book" do
    assert_equal @book, @session.book
  end
end
