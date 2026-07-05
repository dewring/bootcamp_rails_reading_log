class BookProgressJob < ApplicationJob
  include SemanticLogger::Loggable

  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(user, book)
    logger.measure_info(
      "Updating book progress",
      payload: { user_id: user.id, book_id: book.id }
    ) do
      user_book = UserBook.find_or_create_by(user: user, book: book)
      pages_read = ReadingSession.where(user: user, book: book).sum(:pages_read)

      new_status = if book.total_pages && pages_read >= book.total_pages
        "finished"
      else
        "reading"
      end
      user_book.update!(status: new_status) if user_book.status != new_status
    end
  end
end
