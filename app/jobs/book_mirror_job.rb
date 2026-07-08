class BookMirrorJob < ApplicationJob
  include SemanticLogger::Loggable

  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::Error, wait: 30.seconds, attempts: 3

  def perform(book)
    bare_key = book.ol_work_key.delete_prefix("/works/")

    logger.measure_info(
      "Mirroring book from Open Library",
      payload: { book_id: book.id, ol_work_key: book.ol_work_key }
    ) do
      Rails.cache.delete("book:#{bare_key}:mirrored")
      BookMirrorService.new(bare_key).call
    end
  end
end
