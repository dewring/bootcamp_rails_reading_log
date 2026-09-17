require "test_helper"

class ReadingSessionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def setup
    @user = users(:leika)
    @book = books(:refactoring)
    @session = ReadingSession.new(
      user: @user,
      book: @book,
      read_on: Date.today,
      pages_read: 10
    )
  end

  test "valid reading session" do
    assert @session.valid?
  end

  test "invalid without read_on" do
    @session.read_on = nil
    assert_not @session.valid?
  end

  test "invalid without pages_read" do
    @session.pages_read = nil
    assert_not @session.valid?
  end

  test "invalid if pages_read is zero" do
    @session.pages_read = 0
    assert_not @session.valid?
  end

  test "invalid if pages_read is negative" do
    @session.pages_read = -5
    assert_not @session.valid?
  end

  test "notes are optional" do
    @session.notes = nil
    assert @session.valid?
  end

  test "belongs to a user" do
    assert_equal @user, @session.user
  end

  test "belongs to a book" do
    assert_equal @book, @session.book
  end

  test "enqueues BookProgressJob after create" do
    assert_enqueued_with(job: BookProgressJob) do
      @session.save!
    end
  end

  test "enqueues BookProgressJob after update" do
    session = reading_sessions(:one)

    assert_enqueued_with(job: BookProgressJob) do
      session.update!(pages_read: 20)
    end
  end

  test "enqueues BookProgressJob after destroy" do
    session = reading_sessions(:one)

    assert_enqueued_with(job: BookProgressJob) do
      session.destroy
    end
  end

  test "enqueues leaderboard updates for clubs reading the session book" do
    matching_club = BookClub.create!(name: "Matching Club", current_book: @book)
    other_club = BookClub.create!(name: "Other Club", current_book: books(:pragmatic))
    clear_enqueued_jobs

    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ matching_club.id ]) do
      @session.save!
    end

    leaderboard_job_ids = enqueued_jobs.filter_map do |job|
      job[:args].first if job[:job] == BookClubLeaderboardJob
    end
    assert_equal [ matching_club.id ], leaderboard_job_ids
    assert_not_includes leaderboard_job_ids, other_club.id
  end

  test "enqueues leaderboard updates after a session update" do
    session = reading_sessions(:one)
    BookClub.create!(name: "Matching Club", current_book: session.book)

    assert_enqueued_with(job: BookClubLeaderboardJob) do
      session.update!(pages_read: 20)
    end
  end

  test "enqueues leaderboard updates after a session destroy" do
    session = reading_sessions(:one)
    BookClub.create!(name: "Matching Club", current_book: session.book)

    assert_enqueued_with(job: BookClubLeaderboardJob) do
      session.destroy!
    end
  end

  test "does not enqueue a leaderboard update when the transaction rolls back" do
    matching_club = BookClub.create!(name: "Matching Club", current_book: @book)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: BookClubLeaderboardJob) do
      ReadingSession.transaction do
        @session.save!
        raise ActiveRecord::Rollback
      end
    end
    assert_not @session.persisted?
    assert matching_club.persisted?
  end
end
