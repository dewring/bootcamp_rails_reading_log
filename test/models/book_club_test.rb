require "test_helper"

class BookClubTest < ActiveSupport::TestCase
  test "valid book club is valid" do
    assert BookClub.new(name: "Sci-Fi Society").valid?
  end

  test "name must be present" do
    assert_not BookClub.new(name: "").valid?
  end

  test "leaderboard orders members by total pages read, descending" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    leader = users(:leika)
    runner_up = users(:jaina)
    book_club.book_club_memberships.create!(user: leader, role: "owner")
    book_club.book_club_memberships.create!(user: runner_up, role: "member")

    ReadingSession.create!(user: leader, book: books(:refactoring), read_on: Date.today, pages_read: 50)
    ReadingSession.create!(user: runner_up, book: books(:refactoring), read_on: Date.today, pages_read: 20)

    assert_equal [ leader, runner_up ], book_club.leaderboard.to_a
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

    assert_equal 10, book_club.leaderboard.first.total_pages_read.to_i
  end
end
