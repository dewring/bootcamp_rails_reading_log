# Books ranked by reading activity (by read_on) in a report period.
# Ranking before pagination lives in RankedLeaderboard.
class MostReadBooksLeaderboard
  include RankedLeaderboard

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

  def initialize(dates:, sort:)
    @dates = dates
    @sort = selected_sort(sort)
  end

  def ranked_activity
    ranked_relation(book_activity)
      .joins(:book)
      .order(Arel.sql("rank ASC, books.title ASC, books.id ASC"))
  end

  def rows(activity = ranked_activity)
    activity = activity.to_a
    books_by_id = Book.where(id: activity.map(&:book_id)).index_by(&:id)
    activity.map { |book_activity| build_row(book_activity, books_by_id.fetch(book_activity.book_id)) }
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

  def book_activity
    ReadingSession
      .where(read_on: @dates)
      .group(:book_id)
      .select(
        "reading_sessions.book_id",
        "SUM(reading_sessions.pages_read) AS pages_read",
        "COUNT(*) AS sessions",
        "COUNT(DISTINCT reading_sessions.user_id) AS readers",
        rank_expression
      )
  end
end
