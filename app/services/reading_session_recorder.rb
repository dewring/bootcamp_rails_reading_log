class ReadingSessionRecorder
  def initialize(book, user, attributes)
    @book = book
    @user = user
    @attributes = attributes
  end

  def record
    @reading_session = @book.reading_sessions.build(@attributes)
    @reading_session.user = @user

    if @reading_session.save
      move_book_into_reading_status
    end

    @reading_session
  end

  private

  def move_book_into_reading_status
    user_book = @user.user_books.find_or_initialize_by(book: @book)
    return if user_book.persisted? && user_book.status != "want_to_read"

    user_book.status = "reading"
    user_book.save!
  end
end
