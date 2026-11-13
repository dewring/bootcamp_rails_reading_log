require "test_helper"

class PowerUsersLeaderboardTest < ActiveSupport::TestCase
  DATES = Date.new(2025, 1, 1)..Date.new(2025, 1, 7)

  def record_session(user, book, read_on, pages_read)
    ReadingSession.create!(user: users(user), book: books(book), read_on: read_on, pages_read: pages_read)
  end

  test "readers are ranked by distinct active days and tied readers share a rank" do
    record_session(:leika, :refactoring, Date.new(2025, 1, 1), 10)
    record_session(:leika, :refactoring, Date.new(2025, 1, 1), 10)
    record_session(:leika, :pragmatic, Date.new(2025, 1, 2), 10)
    record_session(:jaina, :refactoring, Date.new(2025, 1, 3), 10)
    record_session(:jaina, :refactoring, Date.new(2025, 1, 4), 10)
    record_session(:admin, :pragmatic, Date.new(2025, 1, 5), 10)

    rows = PowerUsersLeaderboard.new(dates: DATES, sort: nil).rows

    assert_equal [ "esperancita", "martita", "theadmin" ], rows.map(&:reader_name)
    assert_equal [ 1, 1, 3 ], rows.map(&:rank)
    leika_row = rows.find { |row| row.user == users(:leika) }
    assert_equal 2, leika_row.active_days
    assert_equal 3, leika_row.sessions
    assert_equal 30, leika_row.pages_read
    assert_equal 2, leika_row.books
  end

  test "sorting by pages read ranks readers by total pages" do
    record_session(:leika, :refactoring, Date.new(2025, 1, 1), 5)
    record_session(:leika, :refactoring, Date.new(2025, 1, 2), 5)
    record_session(:jaina, :pragmatic, Date.new(2025, 1, 1), 300)

    rows = PowerUsersLeaderboard.new(dates: DATES, sort: "pages_read").rows

    assert_equal [ users(:jaina), users(:leika) ], rows.map(&:user)
  end

  test "a reader without a nickname is shown by user ID" do
    users(:jaina).update_column(:nickname, "")
    record_session(:jaina, :pragmatic, Date.new(2025, 1, 1), 5)

    row = PowerUsersLeaderboard.new(dates: DATES, sort: nil).rows.first

    assert_equal "User ##{users(:jaina).id}", row.reader_name
  end

  test "an unknown sort falls back to active days" do
    assert_equal "active_days", PowerUsersLeaderboard.new(dates: DATES, sort: "email").sort
  end
end
