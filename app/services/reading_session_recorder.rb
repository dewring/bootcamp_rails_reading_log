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
      @book.book_clubs.each do |book_club|
        Turbo::StreamsChannel.broadcast_replace_to(
          book_club,
          target: ActionView::RecordIdentifier.dom_id(book_club, :leaderboard),
          partial: "book_clubs/leaderboard",
          locals: { book_club: book_club }
        )
      end
    end
    @reading_session
  end
end
