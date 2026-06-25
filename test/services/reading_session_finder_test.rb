require "test_helper"

class ReadingSessionFinderTest < ActiveSupport::TestCase
  test "normal user only sees their own sessions" do
    user = users(:leika)

    result = ReadingSessionFinder.new(user, {}).find

    assert result.all? { |s| s.user == user }
  end
  test "filters by book_id" do
    user = users(:leika)

    result = ReadingSessionFinder.new(user, { book_id: books(:refactoring).id }).find

    assert result.all? { |s| s.book_id == books(:refactoring).id }
  end
  test "filters by read_on" do
    user = users(:leika)

    result = ReadingSessionFinder.new(user, { read_on: Date.today }).find

    assert result.all? { |s| s.read_on == Date.today }
  end
  test "searches by book title" do
    user = users(:leika)

    result = ReadingSessionFinder.new(user, { q: "Refactoring" }).find

    assert result.any?
  end
end
