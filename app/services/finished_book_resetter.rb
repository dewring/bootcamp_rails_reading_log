class FinishedBookResetter
  def initialize(user:, book:)
    @user = user
    @book = book
  end

  def reset_finished_book
    User.transaction do
      @user.user_books.find_by!(book: @book, status: "finished").destroy!
      @user.reading_sessions.where(book: @book).find_each(&:destroy!)
    end
  end
end
