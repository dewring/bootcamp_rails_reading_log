# Readers ranked by reading activity (by read_on) in a report period.
# Ranking before pagination lives in RankedLeaderboard. Readers are
# shown by nickname, or by user ID when no nickname is set.
class PowerUsersLeaderboard
  include RankedLeaderboard

  DEFAULT_SORT = "active_days"
  SORT_OPTIONS = [
    [ "Active days", "active_days" ],
    [ "Sessions", "sessions" ],
    [ "Pages read", "pages_read" ],
    [ "Books", "books" ]
  ].freeze
  RANK_EXPRESSIONS = {
    "active_days" => Arel.sql("RANK() OVER (ORDER BY COUNT(DISTINCT reading_sessions.read_on) DESC)"),
    "sessions" => Arel.sql("RANK() OVER (ORDER BY COUNT(*) DESC)"),
    "pages_read" => Arel.sql("RANK() OVER (ORDER BY SUM(reading_sessions.pages_read) DESC)"),
    "books" => Arel.sql("RANK() OVER (ORDER BY COUNT(DISTINCT reading_sessions.book_id) DESC)")
  }.freeze

  Row = Data.define(:rank, :user, :active_days, :sessions, :pages_read, :books) do
    def reader_name
      user.nickname.presence || "User ##{user.id}"
    end
  end

  def initialize(dates:, sort:)
    @dates = dates
    @sort = selected_sort(sort)
  end

  def ranked_activity
    ranked_relation(reader_activity)
      .joins(:user)
      .order(Arel.sql("rank ASC, COALESCE(NULLIF(users.nickname, ''), 'User #' || users.id) ASC, users.id ASC"))
  end

  def rows(activity = ranked_activity)
    activity = activity.to_a
    users_by_id = User.where(id: activity.map(&:user_id)).index_by(&:id)
    activity.map { |user_activity| build_row(user_activity, users_by_id.fetch(user_activity.user_id)) }
  end

  private

  def build_row(user_activity, user)
    Row.new(
      rank: user_activity.rank,
      user: user,
      active_days: user_activity.active_days,
      sessions: user_activity.sessions,
      pages_read: user_activity.pages_read,
      books: user_activity.books
    )
  end

  def reader_activity
    ReadingSession
      .where(read_on: @dates)
      .group(:user_id)
      .select(
        "reading_sessions.user_id",
        "COUNT(DISTINCT reading_sessions.read_on) AS active_days",
        "COUNT(*) AS sessions",
        "SUM(reading_sessions.pages_read) AS pages_read",
        "COUNT(DISTINCT reading_sessions.book_id) AS books",
        rank_expression
      )
  end
end
