require "test_helper"

class BookClubCurrentPickJobTest < ActiveJob::TestCase
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "broadcasts a refresh without rendering viewer-specific HTML" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))

    streams = capture_turbo_stream_broadcasts(book_club) do
      BookClubCurrentPickJob.perform_now(book_club.id)
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
      BookClubCurrentPickJob.perform_now(book_club_id)
    end
  end

  test "committed book and deadline changes replace only the discussion current pick card" do
    book_club = BookClub.create!(name: "Live picks", current_book: books(:pragmatic))

    streams = capture_turbo_stream_broadcasts([ book_club, :discussion_current_pick ]) do
      perform_enqueued_jobs(only: BookClubCurrentPickJob) do
        book_club.update!(current_book: books(:refactoring), reading_deadline: Date.new(2026, 12, 15))
      end
    end

    assert_equal 1, streams.size
    stream = streams.first
    assert_equal "replace", stream["action"]
    assert_equal ActionView::RecordIdentifier.dom_id(book_club, :current_pick), stream["target"]
    assert_equal books(:refactoring).title, stream.at_css("template h2 a").text
    assert_equal "2026-12-15", stream.at_css("template time")["datetime"]
    assert stream.at_css("template article.book-club-current-pick-card--discussion")
    assert_nil stream.at_css("template form, template textarea, template turbo-cable-stream-source")
    assert_not_includes stream.text, "Refresh"
  end

  test "a deadline-only change updates the discussion card" do
    book_club = BookClub.create!(name: "Live deadline", current_book: books(:refactoring))

    streams = capture_turbo_stream_broadcasts([ book_club, :discussion_current_pick ]) do
      perform_enqueued_jobs(only: BookClubCurrentPickJob) do
        book_club.update!(reading_deadline: Date.new(2026, 12, 20))
      end
    end

    assert_equal 1, streams.size
    assert_equal "2026-12-20", streams.first.at_css("template time")["datetime"]
  end

  test "clearing a pick and deadline broadcasts the empty state" do
    book_club = BookClub.create!(name: "Cleared pick", current_book: books(:refactoring), reading_deadline: Date.current)

    streams = capture_turbo_stream_broadcasts([ book_club, :discussion_current_pick ]) do
      perform_enqueued_jobs(only: BookClubCurrentPickJob) do
        book_club.update!(current_book: nil, reading_deadline: nil)
      end
    end

    assert_equal 1, streams.size
    assert_includes streams.first.text, "No current pick yet."
    assert_includes streams.first.text, "No reading deadline"
    assert_nil streams.first.at_css("template time")
  end
end
