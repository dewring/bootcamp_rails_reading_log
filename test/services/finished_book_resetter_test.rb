require "test_helper"

class FinishedBookResetterTest < ActiveSupport::TestCase
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
end
