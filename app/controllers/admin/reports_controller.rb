class Admin::ReportsController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin"

  def show
    authorize [ :admin, :report ]
    @as_of = Time.current
    @period = ReportPeriod.new(
      preset: params[:period],
      start_param: params[:start],
      end_param: params[:end],
      today: @as_of.to_date
    )
  end
end
