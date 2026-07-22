class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize UserBook
    @user_books_by_status = policy_scope(UserBook).includes(:book).group_by(&:status)
    @badges = current_user.badges
  end
end
