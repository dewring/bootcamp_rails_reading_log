class ReadingSessionRecorder
  def initialize(book, user, attributes)
    @book = book
    @user = user
    @attributes = attributes
  end

  def record
    @reading_session = @book.reading_sessions.build(@attributes)
    @reading_session.user = @user

    @reading_session.save
    @reading_session
  end
end
