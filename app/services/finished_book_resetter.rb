class FinishedBookResetter
  def initialize(user:, book:)
    @user = user
    @book = book
  end

  def reset_finished_book
    User.transaction do
      # Avoid ReadingSession callbacks scheduling BookProgressJob, which would recreate this book as reading.
      @user.reading_sessions.where(book: @book).delete_all
      @user.user_books.find_by!(book: @book, status: "finished").destroy!
    end
  end
end
