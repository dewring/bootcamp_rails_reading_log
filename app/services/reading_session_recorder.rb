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
      @user.user_books.find_by(book: @book)&.update(status: "reading")
    end
    @reading_session
  end
end
