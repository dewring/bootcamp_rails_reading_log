class Admin::ReportsController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin"

  LEADERBOARDS = {
    "most_read" => MostReadBooksLeaderboard,
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
  end

  private

  # Only known tab names are used; anything else shows the default leaderboard.
  def selected_leaderboard_tab
    requested_tab = params[:tab].to_s
    return requested_tab if LEADERBOARDS.key?(requested_tab)

    DEFAULT_LEADERBOARD
  end
end
