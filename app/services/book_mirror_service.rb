class BookMirrorService
  def initialize(ol_work_key)
    @ol_work_key = ol_work_key.delete_prefix("/works/")
    @client = OpenLibraryClient.new
  end

  def call
    book = Book.find_by(ol_work_key: "/works/#{@ol_work_key}")
    if book.nil?
      work_data = @client.fetch_work(@ol_work_key)

      if work_data.nil?
        Rails.logger.warn(
          event: "book_mirror.degraded",
          ol_work_key: @ol_work_key,
          outcome: "open_library_unavailable_no_local_copy"
        )
      end

      return nil
    end

    unless book.cover_image.attached?
      work_data = @client.fetch_work(@ol_work_key)
      enrich_work(book, work_data) if work_data
    end

    if book.book_editions.empty? || book.book_editions.where(title: [ nil, "" ]).exists?
      editions_data = @client.fetch_editions(@ol_work_key)
      mirror_editions(book, editions_data) if editions_data
    end

    book
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
      edition = BookEdition.find_or_initialize_by(ol_edition_key: entry["key"])
      edition.book         = book
      edition.isbn         = entry["isbn_13"]&.first || entry["isbn_10"]&.first
      edition.title        = entry["title"]
      edition.publisher    = entry["publishers"]&.first
      edition.publish_year = entry["publish_date"]
      edition.page_count   = entry["number_of_pages"]
      edition.language     = entry["languages"]&.first&.dig("key")&.split("/")&.last
      edition.save!
      attach_cover(edition, entry["covers"]&.first)
    end
    Rails.cache.delete("book:#{book.id}:editions:list")
  end

  def attach_cover(record, cover_id)
    return if cover_id.nil?
    return if record.cover_image.attached?
    CoverAttachJob.perform_later(record, cover_id)
  end
end
