require "open-uri"
class CoverNotFoundError < StandardError; end

class CoverAttachJob < ApplicationJob
  include SemanticLogger::Loggable

  discard_on CoverNotFoundError
  discard_on ActiveRecord::RecordNotFound
  retry_on OpenURI::HTTPError, wait: 30.seconds, attempts: 3
  retry_on SocketError, wait: :polynomially_longer, attempts: 5

  queue_as :low

  def perform(record, cover_id)
    return if record.cover_image.attached?

    logger.measure_info(
      "Attaching cover image",
      payload: { record_type: record.class.name, record_id: record.id, cover_id: cover_id }
    ) do
      url = "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"
      record.cover_image.attach(
        io: URI.open(url),
        filename: "cover_#{cover_id}.jpg",
        content_type: "image/jpeg"
      )
    end
  rescue OpenURI::HTTPError => e
    status = e.io.status.first.to_i

    if status < 500
      raise CoverNotFoundError, "Cover not found for cover_id: #{cover_id}"
    else
      raise e
    end
  end
end
