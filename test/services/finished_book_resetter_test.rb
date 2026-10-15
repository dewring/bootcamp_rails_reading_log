require "test_helper"

class FinishedBookResetterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "removes a finished book and all of that user's reading sessions" do
    user = users(:leika)
    book = books(:refactoring)
    user.user_books.find_by!(book: book).update!(status: "finished")

    assert_difference -> { user.reading_sessions.where(book: book).count }, -2 do
      assert_difference -> { user.user_books.where(book: book).count }, -1 do
        FinishedBookResetter.new(user: user, book: book).reset_finished_book
      end
    end

    assert_not user.user_books.exists?(book: book)
    assert_not user.reading_sessions.exists?(book: book)
  end

  test "reset schedules leaderboard challenge and badge updates through session callbacks" do
    user = users(:leika)
    book = books(:refactoring)
    user.user_books.find_by!(book: book).update!(status: "finished")
    club = BookClub.create!(name: "Reset Club", current_book: book)
    club.book_club_memberships.create!(user: user, role: "member")
    other_club = BookClub.create!(name: "Other Club", current_book: books(:pragmatic))
    assert_includes club.leaderboard.map(&:id), user.id
    clear_enqueued_jobs

    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ club.id ]) do
      assert_enqueued_with(job: ChallengeProgressJob, args: [ user ]) do
        assert_enqueued_with(job: BadgeAwardJob, args: [ user ]) do
          FinishedBookResetter.new(user: user, book: book).reset_finished_book
        end
      end
    end

    assert_empty club.leaderboard.to_a
    leaderboard_job_ids = enqueued_jobs.filter_map do |job|
      job[:args].first if job[:job] == BookClubLeaderboardJob
    end
    assert_not_includes leaderboard_job_ids, other_club.id
  end

  test "reset recalculates challenge progress without recreating the removed book" do
    user = users(:leika)
    book = books(:refactoring)
    user.user_books.find_by!(book: book).update!(status: "finished")
    challenge = Challenge.create!(title: "Reset Streak", goal_type: "streak_days", goal_value: 10,
      starts_at: 10.days.ago, ends_at: 10.days.from_now)
    user_challenge = user.user_challenges.create!(challenge: challenge, status: "active")
    ChallengeProgressJob.perform_now(user)
    assert_equal 20, user_challenge.reload.progress
    clear_enqueued_jobs

    perform_enqueued_jobs(only: [ BookProgressJob, ChallengeProgressJob ]) do
      FinishedBookResetter.new(user: user, book: book).reset_finished_book
    end

    assert_equal 0, user_challenge.reload.progress
    assert_equal "active", user_challenge.status
    assert_not user.user_books.exists?(book: book)
  end

  test "reset preserves another reader's sessions and the user's other books" do
    user = users(:leika)
    book = books(:refactoring)
    user.user_books.find_by!(book: book).update!(status: "finished")
    other_reader_session = ReadingSession.create!(user: users(:jaina), book: book, read_on: Date.current, pages_read: 10)
    other_book_session = ReadingSession.create!(user: user, book: books(:pragmatic), read_on: Date.current, pages_read: 10)

    FinishedBookResetter.new(user: user, book: book).reset_finished_book

    assert ReadingSession.exists?(other_reader_session.id)
    assert ReadingSession.exists?(other_book_session.id)
  end

  test "rollback preserves the book and sessions without scheduling updates" do
    user = users(:leika)
    book = books(:refactoring)
    user.user_books.find_by!(book: book).update!(status: "finished")
    BookClub.create!(name: "Rollback Club", current_book: book)
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      User.transaction do
        FinishedBookResetter.new(user: user, book: book).reset_finished_book
        raise ActiveRecord::Rollback
      end
    end

    assert user.user_books.exists?(book: book, status: "finished")
    assert_equal 2, user.reading_sessions.where(book: book).count
  end
end
