# Shared ranking for the admin report leaderboards.
#
# RANK() gives tied rows the same rank and skips the next ones (1, 2, 2, 4).
# Every row whose rank is within TOP_RANK is kept, so a tie at #10 can make a
# list longer than ten rows. Sort keys come from each leaderboard's fixed
# RANK_EXPRESSIONS and map to prebuilt SQL, so request params never reach the
# query text.
module RankedLeaderboard
  TOP_RANK = 10

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

  # A window function's result cannot be filtered in the same query's WHERE,
  # so the grouped, ranked query is wrapped as a subquery first.
  def top_ranked(grouped_activity)
    grouped_activity.klass
      .from(grouped_activity, :ranked_activity)
      .select("ranked_activity.*")
      .where("ranked_activity.rank <= ?", TOP_RANK)
  end
end
