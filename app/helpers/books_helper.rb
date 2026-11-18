module BooksHelper
  BOOK_COVER_FALLBACK_TONE_COUNT = 6

  # Picks one of the pastel fallback tones from a stable seed (such as a book
  # id) so the same book keeps the same color on every page and reload.
  def book_cover_fallback_tone(seed)
    Zlib.crc32(seed.to_s) % BOOK_COVER_FALLBACK_TONE_COUNT
  end

  def book_cover_fallback_initial(title)
    title.to_s[/[[:alnum:]]/].to_s.upcase
  end

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
