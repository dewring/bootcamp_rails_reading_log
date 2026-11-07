require "test_helper"

class BookClubLeaderboardJobTest < ActiveJob::TestCase
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "broadcasts a refresh without rendering viewer-specific HTML" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))

    streams = capture_turbo_stream_broadcasts(book_club) do
      BookClubLeaderboardJob.perform_now(book_club.id)
    end
    assert_equal 1, streams.size
    assert_equal "refresh", streams.first["action"]
    assert_nil streams.first.at_css("template")
  end

  test "skips a club deleted before the job runs" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club_id = book_club.id
    book_club.destroy!

    assert_nothing_raised do
      BookClubLeaderboardJob.perform_now(book_club_id)
    end
  end

  test "a committed reading update changes leaders once while continuing to refresh the leaderboard" do
    book = Book.create!(title: "Job leaderboard book", author: "An Author")
    club = BookClub.create!(name: "Job leaderboard circle", current_book: book)
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")
    ReadingSession.create!(user: users(:leika), book: book, read_on: Date.current, pages_read: 10)
    BookClubLeaderboardJob.perform_now(club.id)
    clear_enqueued_jobs

    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ club.id ]) do
      ReadingSession.create!(user: users(:jaina), book: book, read_on: Date.current, pages_read: 20)
    end

    streams = nil
    assert_difference "BookClubLeaderNotifier.count", 1 do
      assert_enqueued_with(job: Noticed::EventJob) do
        streams = capture_turbo_stream_broadcasts(club) { BookClubLeaderboardJob.perform_now(club.id) }
      end
    end
    assert_equal [ "refresh" ], streams.map { |stream| stream["action"] }
    assert_equal [ users(:jaina).nickname ], BookClubLeaderNotifier.last.params[:leader_names]

    clear_enqueued_jobs
    assert_no_difference "BookClubLeaderNotifier.count" do
      BookClubLeaderboardJob.perform_now(club.id)
    end
    assert_no_enqueued_jobs(only: Noticed::EventJob)
  end
end
