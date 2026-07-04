require "open-uri"

class CoverAttachJob < ApplicationJob
  queue_as :default

  def perform(record, cover_id)
    return if record.cover_image.attached?

    url = "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"
    record.cover_image.attach(
      io: URI.open(url),
      filename: "cover_#{cover_id}.jpg",
      content_type: "image/jpeg"
    )
  rescue => e
    Rails.logger.error("attach_cover failed: #{e.message}")
  end
end
