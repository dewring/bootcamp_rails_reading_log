# Period totals for the admin report, counted straight from reading_sessions
# by read_on. Readers and books are distinct over the whole period, not summed
# from daily values, so a reader active on three dates counts once.
class ReadingActivityTotals
  Totals = Data.define(:active_readers, :sessions, :pages_read, :books)

  def initialize(dates)
    @dates = dates
  end

  def totals
    active_readers, sessions, pages_read, books = ReadingSession
      .where(read_on: @dates)
      .pick(
        Arel.sql("COUNT(DISTINCT user_id)"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(pages_read), 0)"),
        Arel.sql("COUNT(DISTINCT book_id)")
      )

    Totals.new(active_readers: active_readers, sessions: sessions, pages_read: pages_read, books: books)
  end
end
