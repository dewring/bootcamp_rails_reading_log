require "test_helper"

class BookClubCurrentPickJobTest < ActiveJob::TestCase
  test "broadcasts the persisted current-pick panel" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))

    assert_turbo_stream_broadcasts(book_club) do
      BookClubCurrentPickJob.perform_now(book_club.id)
    end
  end

  test "skips a club deleted before the job runs" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club_id = book_club.id
    book_club.destroy!

    assert_nothing_raised do
      BookClubCurrentPickJob.perform_now(book_club_id)
    end
  end
end
