# Books ranked by reading activity (by read_on) in a report period.
#
# RANK() gives tied books the same rank and skips the next ones (1, 2, 2, 4).
# Every book whose rank is within TOP_RANK is kept, so a tie at #10 can make
# the list longer than ten rows. Sort keys come from a fixed list and map to
# prebuilt SQL, so request params never reach the query text.
class MostReadBooksLeaderboard
  TOP_RANK = 10
  DEFAULT_SORT = "pages_read"
  SORT_OPTIONS = [
    [ "Pages read", "pages_read" ],
    [ "Sessions", "sessions" ],
    [ "Readers", "readers" ]
  ].freeze
  RANK_EXPRESSIONS = {
    "pages_read" => Arel.sql("RANK() OVER (ORDER BY SUM(reading_sessions.pages_read) DESC)"),
    "sessions" => Arel.sql("RANK() OVER (ORDER BY COUNT(*) DESC)"),
    "readers" => Arel.sql("RANK() OVER (ORDER BY COUNT(DISTINCT reading_sessions.user_id) DESC)")
  }.freeze

  Row = Data.define(:rank, :book, :pages_read, :sessions, :readers)

  attr_reader :sort

  def initialize(dates:, sort:)
    @dates = dates
    @sort = RANK_EXPRESSIONS.key?(sort.to_s) ? sort.to_s : DEFAULT_SORT
  end

  def rows
    activity = top_ranked_activity.to_a
    books_by_id = Book.where(id: activity.map(&:book_id)).index_by(&:id)
    ranked_rows = activity.map { |book_activity| build_row(book_activity, books_by_id.fetch(book_activity.book_id)) }

    ranked_rows.sort_by { |row| [ row.rank, row.book.title ] }
  end

  private

  def build_row(book_activity, book)
    Row.new(
      rank: book_activity.rank,
      book: book,
      pages_read: book_activity.pages_read,
      sessions: book_activity.sessions,
      readers: book_activity.readers
    )
  end

  def top_ranked_activity
    ReadingSession
      .from(ranked_book_activity, :ranked_book_activity)
      .select("ranked_book_activity.*")
      .where("ranked_book_activity.rank <= ?", TOP_RANK)
  end

  def ranked_book_activity
    ReadingSession
      .where(read_on: @dates)
      .group(:book_id)
      .select(
        "reading_sessions.book_id",
        "SUM(reading_sessions.pages_read) AS pages_read",
        "COUNT(*) AS sessions",
        "COUNT(DISTINCT reading_sessions.user_id) AS readers",
        RANK_EXPRESSIONS.fetch(@sort).as("rank")
      )
  end
end
