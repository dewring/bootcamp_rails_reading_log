# Books ranked by reactions created or changed in a report period.
#
# A reaction is one row per reader and book that is updated in place when the
# reader switches kinds (like -> dislike), so this counts each reaction's
# latest kind by updated_at; earlier kinds are not kept. Only reactions from
# active accounts count, the same rule the public reaction totals use.
# Ranking and the Top 10 tie rule live in RankedLeaderboard.
class MostReactedBooksLeaderboard
  include RankedLeaderboard

  DEFAULT_SORT = "total"
  SORT_OPTIONS = [
    [ "Total reactions", "total" ],
    [ "Likes", "likes" ],
    [ "Dislikes", "dislikes" ]
  ].freeze
  RANK_EXPRESSIONS = {
    "total" => Arel.sql("RANK() OVER (ORDER BY COUNT(*) DESC)"),
    "likes" => Arel.sql("RANK() OVER (ORDER BY COUNT(*) FILTER (WHERE reactions.kind = 'like') DESC)"),
    "dislikes" => Arel.sql("RANK() OVER (ORDER BY COUNT(*) FILTER (WHERE reactions.kind = 'dislike') DESC)")
  }.freeze

  Row = Data.define(:rank, :book, :total, :likes, :dislikes) do
    def other_kinds
      total - likes - dislikes
    end
  end

  def self.reactions_in_period(dates)
    Reaction.eligible.where(updated_at: dates.first.beginning_of_day..dates.last.end_of_day)
  end

  def self.book_count(dates:)
    reactions_in_period(dates).distinct.count(:book_id)
  end

  def initialize(dates:, sort:)
    @dates = dates
    @sort = selected_sort(sort)
  end

  def rows
    activity = top_ranked(book_reactions).to_a
    books_by_id = Book.where(id: activity.map(&:book_id)).index_by(&:id)
    ranked_rows = activity.map { |book_reaction| build_row(book_reaction, books_by_id.fetch(book_reaction.book_id)) }

    ranked_rows.sort_by { |row| [ row.rank, row.book.title ] }
  end

  private

  def build_row(book_reaction, book)
    Row.new(
      rank: book_reaction.rank,
      book: book,
      total: book_reaction.total,
      likes: book_reaction.likes,
      dislikes: book_reaction.dislikes
    )
  end

  def book_reactions
    self.class.reactions_in_period(@dates)
      .group("reactions.book_id")
      .select(
        "reactions.book_id",
        "COUNT(*) AS total",
        "COUNT(*) FILTER (WHERE reactions.kind = 'like') AS likes",
        "COUNT(*) FILTER (WHERE reactions.kind = 'dislike') AS dislikes",
        rank_expression
      )
  end
end
