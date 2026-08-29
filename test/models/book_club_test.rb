require "test_helper"

class BookClubTest < ActiveSupport::TestCase
  test "valid book club is valid" do
    assert BookClub.new(name: "Sci-Fi Society").valid?
  end

  test "name must be present" do
    assert_not BookClub.new(name: "").valid?
  end

  test "leaderboard ranks members by furthest page reached, not total pages logged" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    leader = users(:leika)
    runner_up = users(:jaina)
    book_club.book_club_memberships.create!(user: leader, role: "owner")
    book_club.book_club_memberships.create!(user: runner_up, role: "member")

    # runner_up logged more sessions but never read as far into the book
    ReadingSession.create!(user: runner_up, book: books(:refactoring), read_on: 2.days.ago, pages_read: 30)
    ReadingSession.create!(user: runner_up, book: books(:refactoring), read_on: Date.today, pages_read: 40)
    ReadingSession.create!(user: leader, book: books(:refactoring), read_on: Date.today, pages_read: 60)

    assert_equal [ leader, runner_up ], book_club.leaderboard.to_a
    assert_equal 60, book_club.leaderboard.first.furthest_page_read.to_i
  end

  test "leaderboard excludes non-members even for the same book" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    member = users(:leika)
    outsider = users(:jaina)
    book_club.book_club_memberships.create!(user: member, role: "owner")

    ReadingSession.create!(user: member, book: books(:refactoring), read_on: Date.today, pages_read: 10)
    ReadingSession.create!(user: outsider, book: books(:refactoring), read_on: Date.today, pages_read: 999)

    assert_equal [ member ], book_club.leaderboard.to_a
  end

  test "leaderboard excludes sessions for books other than the current pick" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    member = users(:jaina)
    book_club.book_club_memberships.create!(user: member, role: "owner")

    ReadingSession.create!(user: member, book: books(:refactoring), read_on: Date.today, pages_read: 10)
    ReadingSession.create!(user: member, book: books(:pragmatic), read_on: Date.today, pages_read: 999)

    assert_equal 10, book_club.leaderboard.first.furthest_page_read.to_i
  end
end
