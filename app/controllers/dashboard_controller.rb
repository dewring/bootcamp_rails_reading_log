class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize UserBook
    user_books = policy_scope(UserBook)
      .includes(book: { cover_image_attachment: :blob })
      .to_a
    reading_book_ids = policy_scope(ReadingSession)
      .where(book_id: user_books.map(&:book_id))
      .distinct
      .pluck(:book_id)

    @reading_books, @want_to_read_books = user_books.partition do |user_book|
      user_book.status != "finished" && (user_book.status == "reading" || reading_book_ids.include?(user_book.book_id))
    end
    @want_to_read_books.select! { |user_book| user_book.status == "want_to_read" }
  end
end
