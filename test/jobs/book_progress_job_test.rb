require "test_helper"

class BookProgressJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "transitions want_to_read to reading when a session is logged" do
    user_book = users(:leika).user_books.find_or_create_by!(book: books(:refactoring))
    user_book.update!(status: "want_to_read")
    ReadingSession.create!(user: users(:leika), book: books(:refactoring), read_on: Date.today, pages_read: 50)

    BookProgressJob.new.perform(users(:leika), books(:refactoring))

    assert_equal "reading", user_book.reload.status
  end

  test "transitions reading to finished when total pages reached" do
    user_book = users(:leika).user_books.find_or_create_by!(book: books(:refactoring))
    user_book.update!(status: "reading")
    ReadingSession.create!(user: users(:leika), book: books(:refactoring), read_on: Date.today, pages_read: 448)

    BookProgressJob.new.perform(users(:leika), books(:refactoring))

    assert_equal "finished", user_book.reload.status
  end
  test "does not finish when total_pages is nil" do
    book = Book.create!(title: "No Page Count", author: "Someone", total_pages: nil)
    user_book = UserBook.create!(user: users(:leika), book: book, status: "reading")
    ReadingSession.create!(user: users(:leika), book: book, read_on: Date.today, pages_read: 99999)

    BookProgressJob.new.perform(users(:leika), book)

    assert_equal "reading", user_book.reload.status
  end

  test "creates UserBook if one does not already exist" do
    book = Book.create!(title: "Brand New Book", author: "Someone", total_pages: 100)
    ReadingSession.create!(user: users(:leika), book: book, read_on: Date.today, pages_read: 20)

    assert_difference "UserBook.count", 1 do
      BookProgressJob.new.perform(users(:leika), book)
    end

    assert UserBook.exists?(user: users(:leika), book: book)
  end
  test "discards job when book no longer exists" do
    book = Book.create!(title: "Temp", author: "Temp")
    book.destroy

    assert_nothing_raised do
      perform_enqueued_jobs do
        BookProgressJob.perform_later(users(:leika), book)
      end
    end
  end
end
