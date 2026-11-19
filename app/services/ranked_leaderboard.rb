# Shared ranking for the admin report leaderboards.
#
# RANK() gives tied rows the same rank and skips the next ones (1, 2, 2, 4).
# Sort keys come from each leaderboard's fixed RANK_EXPRESSIONS, so request
# params never reach the query text. Rank the full result before pagination.
module RankedLeaderboard
  RANK_DIRECTIONS = [ "desc", "asc" ].freeze

  attr_reader :sort, :direction

  def sort_options
    self.class::SORT_OPTIONS
  end

  private

  def selected_sort(requested_sort)
    requested = requested_sort.to_s
    return requested if self.class::RANK_EXPRESSIONS.key?(requested)

    self.class::DEFAULT_SORT
  end

  def selected_direction(requested_direction)
    requested_direction.to_s.presence_in(RANK_DIRECTIONS) || "desc"
  end

  # Highest first ("desc") keeps rank 1 on top. Lowest first reverses the list,
  # while every row keeps its rank number, so "1" always means the highest value.
  def rank_order
    direction == "asc" ? Arel.sql("rank DESC") : Arel.sql("rank ASC")
  end

  def rank_expression
    self.class::RANK_EXPRESSIONS.fetch(sort).as("rank")
  end

  # Keep grouping and ranking inside the subquery, so an outer LIMIT/OFFSET
  # pages the results without restarting ranks on each page.
  def ranked_relation(grouped_activity)
    table_name = grouped_activity.klass.table_name
    grouped_activity.klass
      .from(grouped_activity, table_name)
      .select("#{table_name}.*")
  end
end
