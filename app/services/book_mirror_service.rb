require "open-uri"

class BookMirrorService
  def initialize(ol_work_key)
    @ol_work_key = ol_work_key
    @client = OpenLibraryClient.new
  end

  def call
    Rails.cache.fetch("book:#{@ol_work_key}:mirrored", expires_in: 24.hours) do
      work_data = @client.fetch_work(@ol_work_key)
      return nil if work_data.nil?

      book = Book.find_by(ol_work_key: "/works/#{@ol_work_key}")
      return nil if book.nil?

      enrich_work(book, work_data)

      editions_data = @client.fetch_editions(@ol_work_key)
      mirror_editions(book, editions_data) if editions_data

      book
    end
  end

  private

  def enrich_work(book, work_data)
    description = work_data["description"]
    description = description["value"] if description.is_a?(Hash)

    book.update(
      description: description,
      subjects: (work_data["subjects"] || []).first(5)
    )

    attach_cover(book, work_data["covers"]&.first)
  end

  def mirror_editions(book, editions_data)
    editions_data["entries"]&.each do |entry|
      edition = BookEdition.find_or_create_by(ol_edition_key: entry["key"]) do |e|
        e.book         = book
        e.isbn         = entry["isbn_13"]&.first || entry["isbn_10"]&.first
        e.publisher    = entry["publishers"]&.first
        e.publish_year = entry["publish_date"]
        e.page_count   = entry["number_of_pages"]
        e.language     = entry["languages"]&.first&.dig("key")&.split("/")&.last
      end
      attach_cover(edition, entry["covers"]&.first)
    end
    Rails.cache.delete("book:#{book.id}:editions:list")
  end

  def attach_cover(record, cover_id)
    return if cover_id.nil?
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
