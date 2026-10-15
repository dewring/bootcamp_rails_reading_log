require "test_helper"
class ReadingSessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end
  test "new reading session defaults to today's date" do
    sign_in users(:leika)
    get new_book_reading_session_path(book_id: books(:refactoring))
    assert_response :success
    assert_select "input[type='date'][value='#{Date.today}']"
  end

  test "reading journal shows saved history" do
    sign_in users(:leika)
    get book_reading_journal_path(books(:refactoring))
    assert_response :success
    assert_select ".reading-detail-page"
    assert_select "h2#reading-detail-title", text: books(:refactoring).title
    assert_select "#reading-record"
    assert_select "#reading-history-title", text: "Reading history"
    assert_select ".reading-detail-timeline-item", count: 2
    assert_select ".reading-detail-history-footer"
    assert_select ".reading-detail-entry-actions", count: 0
    assert_select ".reading-detail-empty-state", count: 0
  end

  test "reading journal shows empty state without history" do
    sign_in users(:leika)
    get book_reading_journal_path(books(:pragmatic))
    assert_response :success
    assert_select ".reading-detail-empty-state"
    assert_select ".reading-detail-empty-state h4", text: "No reading records yet"
    assert_select ".reading-detail-status", text: "0 entries"
    assert_select ".reading-detail-history-footer"
  end

  test "history page shows badges and finished books sections" do
    sign_in users(:leika)
    get reading_sessions_path

    assert_response :success
    assert_select ".history-page"
    assert_select "#history-badges-title", text: "Badges"
    assert_select ".history-badge-card", count: Badge.count
    assert_select "#history-finished-title", text: "Finished books"
    assert_select "a.my-log-navigation-item--active[href='#{reading_sessions_path}']", text: "History"
    assert_select ".my-log-empty-shelf", text: "No finished books yet."
    assert_select ".my-log-empty-shelf a", count: 0
    assert_select ".history-position", count: 0
    assert_select ".my-log-season-note strong", text: /finished book/
  end

  test "finished books link back to their reading journal history" do
    sign_in users(:leika)
    book = books(:pragmatic)
    users(:leika).user_books.find_by!(book: book).update!(status: "finished")
    ReadingSession.create!(user: users(:leika), book: book, read_on: Date.today, pages_read: 10)

    get reading_sessions_path

    assert_select ".history-finished-carousel a[href='#{book_finished_journal_path(book)}']", count: 1
    assert_select ".history-finished-carousel a[href='#{book_reading_journal_path(book)}']", count: 0
  end

  test "finished journal shows history without a reading record form" do
    sign_in users(:leika)
    book = books(:refactoring)
    users(:leika).user_books.find_by!(book: book).update!(status: "finished")

    get book_finished_journal_path(book)

    assert_response :success
    assert_select ".reading-detail-page--finished"
    assert_select "h2#reading-detail-title", text: book.title
    assert_select "a.my-log-navigation-item--active[href='#{reading_sessions_path}']", text: "History"
    assert_select "a.my-log-navigation-item--active[href='#{dashboard_path}']", count: 0
    assert_select "#reading-record", count: 0
    assert_select "#reading-history-title", text: "Reading history"
    assert_select ".reading-detail-status", text: "3 entries"
    assert_select ".reading-detail-timeline-item", count: 3
    assert_select ".reading-detail-entry--finished h4", text: "Finished reading"
    assert_select ".reading-detail-entry--finished .reading-detail-status", text: "Earned"
    assert_select ".reading-detail-action--delete", count: 1
  end

  test "deleting a finished journal resets the book for a new reading" do
    sign_in users(:leika)
    book = books(:refactoring)
    user_book = users(:leika).user_books.find_by!(book: book)
    user_book.update!(status: "finished")

    delete book_finished_journal_path(book)

    assert_redirected_to book_path(book)
    assert_not UserBook.exists?(user_book.id)
    assert_not ReadingSession.exists?(user: users(:leika), book: book)

    follow_redirect!
    assert_select "a.book-detail-button-primary", text: /Start Reading/
    assert_select "button.book-detail-button-secondary", text: /Want to Read/
  end

  test "reading shelf links reading books to the reading journal" do
    sign_in users(:leika)
    get dashboard_path
    assert_response :success
    assert_select "a[href='#{book_reading_journal_path(books(:refactoring))}']"
  end

  test "reading journal save returns to the reading journal" do
    sign_in users(:leika)
    post book_reading_sessions_path(books(:refactoring)), params: {
      return_to: "reading_journal",
      reading_session: { read_on: Date.today, pages_read: 12, notes: "A focused reading session." }
    }
    assert_redirected_to book_reading_journal_path(books(:refactoring))
  end

  test "guest cannot access reading sessions" do
    get new_book_reading_session_path(book_id: books(:refactoring))
    assert_redirected_to new_user_session_path
  end
  test "create reading session shows errors on invalid submission" do
    sign_in users(:leika)
    post book_reading_sessions_path(books(:refactoring)), params: { reading_session: { read_on: "", pages_read: "" } }
    assert_response :unprocessable_entity
    assert_select "div.error-messages"
  end

  test "user create reading session" do
    sign_in users(:leika)
    post book_reading_sessions_path(books(:refactoring)), params: { reading_session: { read_on: Date.today, pages_read: 15 } }
    assert_redirected_to dashboard_path
  end
  test "user update reading session" do
    sign_in users(:leika)
    patch reading_session_path(reading_sessions(:one)), params: { reading_session: { pages_read: 20 } }
    assert_redirected_to dashboard_path
  end
  test "user destroy book log" do
    sign_in users(:leika)
    delete reading_session_path(reading_sessions(:one))
    assert_redirected_to dashboard_path
  end

  test "create enqueues BookProgressJob" do
    sign_in users(:leika)

    assert_enqueued_with(job: BookProgressJob) do
      post book_reading_sessions_path(books(:refactoring)), params: { reading_session: { read_on: Date.today, pages_read: 15 } }
    end
  end
end
