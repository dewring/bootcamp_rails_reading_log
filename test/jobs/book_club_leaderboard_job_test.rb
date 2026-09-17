require "test_helper"

class BookClubLeaderboardJobTest < ActiveJob::TestCase
  test "broadcasts the persisted leaderboard panel" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))

    assert_turbo_stream_broadcasts(book_club) do
      BookClubLeaderboardJob.perform_now(book_club.id)
    end
  end

  test "skips a club deleted before the job runs" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club_id = book_club.id
    book_club.destroy!

    assert_nothing_raised do
      BookClubLeaderboardJob.perform_now(book_club_id)
    end
  end
end
