# Shared ranking for the admin report leaderboards.
#
# RANK() gives tied rows the same rank and skips the next ones (1, 2, 2, 4).
# Sort keys come from each leaderboard's fixed RANK_EXPRESSIONS, so request
# params never reach the query text. Rank the full result before pagination.
module RankedLeaderboard
  attr_reader :sort

  def sort_options
    self.class::SORT_OPTIONS
  end

  private

  def selected_sort(requested_sort)
    requested = requested_sort.to_s
    return requested if self.class::RANK_EXPRESSIONS.key?(requested)

    self.class::DEFAULT_SORT
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
