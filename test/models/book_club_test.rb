require "test_helper"

class BookClubTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

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

  test "leaderboard gives tied members the same rank" do
    current_book = Book.create!(title: "Leaderboard Tie Book", author: "Test Author")
    book_club = BookClub.create!(name: "Tie Test Club", current_book: current_book)
    member_one = users(:leika)
    member_two = users(:jaina)
    book_club.book_club_memberships.create!(user: member_one, role: "owner")
    book_club.book_club_memberships.create!(user: member_two, role: "member")
    ReadingSession.create!(user: member_one, book: current_book, read_on: Date.today, pages_read: 50)
    ReadingSession.create!(user: member_two, book: current_book, read_on: Date.today, pages_read: 50)

    ranks = book_club.leaderboard.map(&:rank)

    assert_equal [ 1, 1 ], ranks
  end

  test "changing the current pick refreshes both live panels after commit" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(current_book: books(:pragmatic))

    assert_enqueued_with(job: BookClubCurrentPickJob, args: [ book_club.id ])
    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ book_club.id ])
  end

  test "clearing the current pick refreshes both live panels after commit" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(current_book: nil)

    assert_enqueued_with(job: BookClubCurrentPickJob, args: [ book_club.id ])
    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ book_club.id ])
  end

  test "changing only the deadline refreshes the current-pick panel" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(reading_deadline: Date.current + 7.days)

    assert_enqueued_with(job: BookClubCurrentPickJob, args: [ book_club.id ])
    assert_no_enqueued_jobs(only: BookClubLeaderboardJob)
  end

  test "unrelated club changes do not refresh live panels" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(name: "New Name")

    assert_no_enqueued_jobs(only: [ BookClubCurrentPickJob, BookClubLeaderboardJob ])
  end

  test "club panel jobs are not enqueued when the update rolls back" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    BookClub.transaction do
      book_club.update!(current_book: books(:pragmatic))
      raise ActiveRecord::Rollback
    end

    assert_no_enqueued_jobs(only: [ BookClubCurrentPickJob, BookClubLeaderboardJob ])
    assert_equal books(:refactoring), book_club.reload.current_book
  end
end
