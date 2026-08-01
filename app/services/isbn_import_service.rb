class IsbnImportService
  include SemanticLogger::Loggable

  def initialize(isbn)
    @isbn = isbn.to_s.strip.delete(" -")
    @client = OpenLibraryClient.new
  end

  def import_edition
    logger.measure_info(
      "Importing book by ISBN",
      payload: { event: "isbn_import.import_edition", isbn: @isbn }
    ) do
      existing_edition = BookEdition.find_by(isbn: @isbn)
      next existing_edition if existing_edition

      edition_data = @client.fetch_by_isbn(@isbn)
      next nil if edition_data.nil?

      work_key = edition_data.dig("works", 0, "key")
      next nil if work_key.blank?

      doc = {
        "key" => work_key,
        "title" => edition_data["title"],
        "author_name" => [ author_name_for(edition_data, work_key) ]
      }
      book = Book.find_or_create_from_search_result(doc)
      next nil unless book&.persisted?

      BookMirrorService.new(work_key).call_for_isbn(@isbn)
    end
  end

  private

  # Edition records rarely carry a free-text "by_statement" — most only
  # reference an author key, which must be resolved via a separate call.
  # Some editions (e.g. "The Hunger Games", ISBN 9780439023481) have no
  # author info at all — neither "by_statement" nor "authors" — the author
  # only exists on the Work record, and in a differently-nested shape there
  # (work["authors"][0]["author"]["key"], not edition["authors"][0]["key"]).
  def author_name_for(edition_data, work_key)
    return edition_data["by_statement"] if edition_data["by_statement"].present?

    author_key = edition_data.dig("authors", 0, "key")
    if author_key.blank?
      work_data = @client.fetch_work(work_key.delete_prefix("/works/"))
      author_key = work_data&.dig("authors", 0, "author", "key")
    end
    return nil if author_key.blank?

    author_data = @client.fetch_author(author_key.delete_prefix("/authors/"))
    author_data && author_data["name"]
  end
end
