module BooksHelper
  BOOK_COVER_FALLBACK_TONE_COUNT = 6
  CATALOG_SORT_FIELDS = { "title" => "Title", "author" => "Author" }.freeze
  CATALOG_SORT_DIRECTION_LABELS = { "asc" => "A–Z", "desc" => "Z–A" }.freeze

  # Names both the field and the direction, so the sort control always says
  # exactly how the catalog is ordered (for example "Author Z–A").
  def catalog_sort_label(sort, direction)
    "#{CATALOG_SORT_FIELDS.fetch(sort)} #{CATALOG_SORT_DIRECTION_LABELS.fetch(direction)}"
  end

  # Picks one of the pastel fallback tones from a stable seed (such as a book
  # id) so the same book keeps the same color on every page and reload.
  def book_cover_fallback_tone(seed)
    Zlib.crc32(seed.to_s) % BOOK_COVER_FALLBACK_TONE_COUNT
  end

  # Open Library descriptions end with a "([source](url))" credit; this returns
  # only the reader-facing text.
  def book_description_without_source(book)
    book.description.to_s.gsub(/\(\[source\]\(.*?\)\)/, "").strip
  end

  # A short plain-text teaser for banners: drops the source credit and the
  # Markdown emphasis markers (** and __) that Open Library descriptions use.
  def book_description_excerpt(book, length: 160)
    plain_text = book_description_without_source(book).gsub(/(\*\*|__)/, "").squish
    truncate(plain_text, length: length, separator: " ")
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
