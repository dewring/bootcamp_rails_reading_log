class BookClubLeaderboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book_club

  def show
    authorize @book_club, :leaderboard?
    @leaderboard = @book_club.leaderboard.preload(avatar_attachment: :blob).to_a
  end

  private

  def set_book_club
    @book_club = BookClub.find(params[:book_club_id])
  end
end
