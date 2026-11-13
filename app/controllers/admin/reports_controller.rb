class Admin::ReportsController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin"

  LEADERBOARDS = {
    "most_read" => MostReadBooksLeaderboard,
    "most_reactions" => MostReactedBooksLeaderboard,
    "power_users" => PowerUsersLeaderboard
  }.freeze
  DEFAULT_LEADERBOARD = "most_read"

  def show
    authorize [ :admin, :report ]
    @as_of = Time.current
    @period = ReportPeriod.new(
      preset: params[:period],
      start_param: params[:start],
      end_param: params[:end],
      today: @as_of.to_date
    )
    @totals = ReadingActivityTotals.new(@period.dates).totals
    @leaderboard_tab = selected_leaderboard_tab
    @leaderboard = LEADERBOARDS.fetch(@leaderboard_tab).new(dates: @period.dates, sort: params[:sort])
    @pagy, activity = pagy(:offset, @leaderboard.ranked_activity, limit: 10)
    @leaderboard_rows = @leaderboard.rows(activity)
    @reacted_book_count = MostReactedBooksLeaderboard.book_count(dates: @period.dates)
    @import_completeness = CatalogImportCompleteness.new.completeness
    @metric_freshness = ReadingMetricFreshness.new(as_of: @as_of).freshness
  end

  private

  # Only known tab names are used; anything else shows the default leaderboard.
  def selected_leaderboard_tab
    requested_tab = params[:tab].to_s
    return requested_tab if LEADERBOARDS.key?(requested_tab)

    DEFAULT_LEADERBOARD
  end
end
