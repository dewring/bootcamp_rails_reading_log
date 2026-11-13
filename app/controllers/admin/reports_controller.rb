class Admin::ReportsController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin"

  def show
    authorize [ :admin, :report ]
  end
end
