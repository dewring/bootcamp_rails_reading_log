require "test_helper"

class ReadingActivityTotalsTest < ActiveSupport::TestCase
  DATES = Date.new(2025, 1, 1)..Date.new(2025, 1, 3)

  def record_session(user, book, read_on, pages_read)
    ReadingSession.create!(user: users(user), book: books(book), read_on: read_on, pages_read: pages_read)
  end

  test "readers and books are counted once across the period while sessions and pages are summed" do
    record_session(:leika, :refactoring, Date.new(2025, 1, 1), 10)
    record_session(:leika, :refactoring, Date.new(2025, 1, 2), 20)
    record_session(:leika, :pragmatic, Date.new(2025, 1, 3), 5)
    record_session(:jaina, :refactoring, Date.new(2025, 1, 3), 7)

    totals = ReadingActivityTotals.new(DATES).totals

    assert_equal 2, totals.active_readers
    assert_equal 4, totals.sessions
    assert_equal 42, totals.pages_read
    assert_equal 2, totals.books
  end

  test "sessions on the dates just outside the period are not counted" do
    record_session(:leika, :refactoring, Date.new(2024, 12, 31), 10)
    record_session(:jaina, :pragmatic, Date.new(2025, 1, 4), 10)
    record_session(:jaina, :pragmatic, Date.new(2025, 1, 2), 3)

    totals = ReadingActivityTotals.new(DATES).totals

    assert_equal 1, totals.sessions
    assert_equal 3, totals.pages_read
  end

  test "a period with no sessions returns zeros instead of nil" do
    totals = ReadingActivityTotals.new(DATES).totals

    assert_equal 0, totals.active_readers
    assert_equal 0, totals.sessions
    assert_equal 0, totals.pages_read
    assert_equal 0, totals.books
  end
end
