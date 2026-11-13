require "test_helper"

class MostReadBooksLeaderboardTest < ActiveSupport::TestCase
  DATES = Date.new(2025, 1, 1)..Date.new(2025, 1, 7)

  def record_session(user, book, read_on, pages_read)
    ReadingSession.create!(user: user, book: book, read_on: read_on, pages_read: pages_read)
  end

  def build_books(count)
    Array.new(count) { |index| Book.create!(title: "Leaderboard Book #{format('%02d', index + 1)}", author: "Report Author") }
  end

  test "books are ranked by pages read and tied books share a rank while the next rank is skipped" do
    first, tied_a, tied_b, last = build_books(4)
    record_session(users(:leika), first, Date.new(2025, 1, 1), 50)
    record_session(users(:leika), tied_a, Date.new(2025, 1, 2), 30)
    record_session(users(:jaina), tied_b, Date.new(2025, 1, 2), 30)
    record_session(users(:jaina), last, Date.new(2025, 1, 3), 10)

    rows = MostReadBooksLeaderboard.new(dates: DATES, sort: nil).rows

    assert_equal [ first, tied_a, tied_b, last ], rows.map(&:book)
    assert_equal [ 1, 2, 2, 4 ], rows.map(&:rank)
  end

  test "all ranks remain available including books below rank 10" do
    books = build_books(12)
    books.first(9).each_with_index { |book, index| record_session(users(:leika), book, Date.new(2025, 1, 1), 100 - index) }
    record_session(users(:leika), books[9], Date.new(2025, 1, 1), 5)
    record_session(users(:leika), books[10], Date.new(2025, 1, 1), 5)
    record_session(users(:leika), books[11], Date.new(2025, 1, 1), 1)

    rows = MostReadBooksLeaderboard.new(dates: DATES, sort: "pages_read").rows

    assert_equal 12, rows.size
    assert_equal [ 10, 10, 12 ], rows.last(3).map(&:rank)
    assert_includes rows.map(&:book), books[11]
  end

  test "sorting by sessions ranks by session count and counts readers and pages per book" do
    many_sessions, many_pages = build_books(2)
    record_session(users(:leika), many_sessions, Date.new(2025, 1, 1), 5)
    record_session(users(:jaina), many_sessions, Date.new(2025, 1, 2), 5)
    record_session(users(:jaina), many_sessions, Date.new(2025, 1, 3), 5)
    record_session(users(:leika), many_pages, Date.new(2025, 1, 1), 200)

    rows = MostReadBooksLeaderboard.new(dates: DATES, sort: "sessions").rows

    assert_equal [ many_sessions, many_pages ], rows.map(&:book)
    assert_equal [ 3, 1 ], rows.map(&:sessions)
    assert_equal [ 2, 1 ], rows.map(&:readers)
    assert_equal [ 15, 200 ], rows.map(&:pages_read)
  end

  test "an unknown or injected sort falls back to pages read" do
    leaderboard = MostReadBooksLeaderboard.new(dates: DATES, sort: "pages_read DESC; DROP TABLE books")

    assert_equal "pages_read", leaderboard.sort
    assert_empty leaderboard.rows
  end

  test "sessions outside the period are not ranked" do
    inside, outside = build_books(2)
    record_session(users(:leika), inside, Date.new(2025, 1, 7), 10)
    record_session(users(:leika), outside, Date.new(2025, 1, 8), 500)

    rows = MostReadBooksLeaderboard.new(dates: DATES, sort: nil).rows

    assert_equal [ inside ], rows.map(&:book)
  end
  test "database pages split tied books consistently and keep their overall ranks" do
    report_books = build_books(12)
    report_books.each_with_index do |book, index|
      pages = index < 9 ? 100 - index : 5
      record_session(users(:leika), book, DATES.first, pages)
    end
    leaderboard = MostReadBooksLeaderboard.new(dates: DATES, sort: nil)
    first_page = leaderboard.rows(leaderboard.ranked_activity.limit(10))
    second_page = leaderboard.rows(leaderboard.ranked_activity.limit(10).offset(10))

    assert_equal report_books.first(10), first_page.map(&:book)
    assert_equal report_books.last(2), second_page.map(&:book)
    assert_equal 10, first_page.last.rank
    assert_equal [ 10, 10 ], second_page.map(&:rank)
  end
end
