require "test_helper"

class MostReactedBooksLeaderboardTest < ActiveSupport::TestCase
  DATES = Date.new(2025, 1, 1)..Date.new(2025, 1, 7)

  def react(user, book, kind, updated_at)
    reaction = Reaction.create!(user: users(user), book: books(book), kind: kind)
    reaction.update_column(:updated_at, updated_at)
    reaction
  end

  test "books are ranked by total reactions with likes and dislikes counted by latest kind" do
    react(:leika, :refactoring, "like", Time.zone.local(2025, 1, 2, 9))
    react(:jaina, :refactoring, "dislike", Time.zone.local(2025, 1, 3, 9))
    react(:admin, :refactoring, "love", Time.zone.local(2025, 1, 3, 10))
    react(:leika, :pragmatic, "like", Time.zone.local(2025, 1, 4, 9))

    rows = MostReactedBooksLeaderboard.new(dates: DATES, sort: nil).rows

    assert_equal [ books(:refactoring), books(:pragmatic) ], rows.map(&:book)
    assert_equal [ 3, 1 ], rows.map(&:total)
    assert_equal [ 1, 1 ], rows.map(&:likes)
    assert_equal [ 1, 0 ], rows.map(&:dislikes)
    assert_equal [ 1, 0 ], rows.map(&:other_kinds)
  end

  test "sorting by likes ranks books by like count and tied books share a rank" do
    react(:leika, :refactoring, "like", Time.zone.local(2025, 1, 2, 9))
    react(:jaina, :refactoring, "dislike", Time.zone.local(2025, 1, 2, 9))
    react(:leika, :pragmatic, "like", Time.zone.local(2025, 1, 2, 9))

    rows = MostReactedBooksLeaderboard.new(dates: DATES, sort: "likes").rows

    assert_equal [ 1, 1 ], rows.map(&:rank)
  end

  test "reactions last updated within the first and last day count and ones just outside do not" do
    react(:leika, :refactoring, "like", Time.zone.local(2025, 1, 1, 0, 0, 0))
    react(:jaina, :refactoring, "like", Time.zone.local(2025, 1, 7, 23, 59, 59))
    react(:admin, :refactoring, "like", Time.zone.local(2025, 1, 8, 0, 0, 0))
    react(:leika, :pragmatic, "like", Time.zone.local(2024, 12, 31, 23, 59, 59))

    rows = MostReactedBooksLeaderboard.new(dates: DATES, sort: nil).rows

    assert_equal [ books(:refactoring) ], rows.map(&:book)
    assert_equal [ 2 ], rows.map(&:total)
    assert_equal 1, MostReactedBooksLeaderboard.book_count(dates: DATES)
  end

  test "a reaction switched from like to dislike during the period counts once as a dislike" do
    reaction = react(:leika, :refactoring, "like", Time.zone.local(2024, 12, 1, 9))
    reaction.update!(kind: "dislike", updated_at: Time.zone.local(2025, 1, 3, 9))

    row = MostReactedBooksLeaderboard.new(dates: DATES, sort: nil).rows.first

    assert_equal 1, row.total
    assert_equal 0, row.likes
    assert_equal 1, row.dislikes
  end

  test "reactions from suspended accounts are not counted" do
    users(:jaina).update_column(:account_status, "suspended")
    react(:jaina, :refactoring, "like", Time.zone.local(2025, 1, 2, 9))

    assert_empty MostReactedBooksLeaderboard.new(dates: DATES, sort: nil).rows
    assert_equal 0, MostReactedBooksLeaderboard.book_count(dates: DATES)
  end
end
