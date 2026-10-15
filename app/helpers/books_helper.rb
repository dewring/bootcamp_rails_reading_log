module BooksHelper
  def admin_catalog_metadata(book)
    edition = book.book_editions.first
    pages = book.total_pages.presence || edition&.page_count.presence
    [
      book.genres.map(&:name).presence&.join(" · ") || "Genre not set",
      edition&.language.presence || "Language not set",
      pages ? "#{pages}p" : "Pages not set"
    ].join(" · ")
  end
end
