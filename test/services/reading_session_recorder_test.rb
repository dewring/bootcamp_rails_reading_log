require "test_helper"

class ReadingSessionRecorderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "successfully records a reading session" do
    book = books(:refactoring)
    user = users(:leika)
    attributes = { read_on: Date.today, pages_read: 10 }

    reading_session = ReadingSessionRecorder.new(book, user, attributes).record

    assert reading_session.persisted?
  end

  test "does not record a reading session with invalid attributes" do
    book = books(:refactoring)
    user = users(:leika)
    attributes = { read_on: Date.today, pages_read: -1 }

    reading_session = ReadingSessionRecorder.new(book, user, attributes).record

    refute reading_session.persisted?
  end

  test "enqueues a leaderboard update when logging a session for a club's current pick" do
    book = books(:refactoring)
    user = users(:leika)
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: book)
    book_club.book_club_memberships.create!(user: user, role: "owner")
    attributes = { read_on: Date.today, pages_read: 10 }
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: BookClubLeaderboardJob do
      ReadingSessionRecorder.new(book, user, attributes).record
    end
  end

  test "does not enqueue a leaderboard update when the book isn't the club's current pick" do
    book1 = books(:refactoring)
    book2 = books(:pragmatic)
    user = users(:leika)
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: book1)
    book_club.book_club_memberships.create!(user: user, role: "owner")
    attributes = { read_on: Date.today, pages_read: 10 }

    assert_no_enqueued_jobs(only: BookClubLeaderboardJob) do
      ReadingSessionRecorder.new(book2, user, attributes).record
    end
  end
end
