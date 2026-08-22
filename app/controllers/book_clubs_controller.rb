class BookClubsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book_club, only: [ :show, :join, :leave, :set_current_book ]

  def index
    @book_clubs = policy_scope(BookClub)
  end

  def show
    authorize @book_club
  end

  def new
    @book_club = BookClub.new
    authorize @book_club
  end

  def create
    @book_club = BookClub.new(book_club_params)
    authorize @book_club

    BookClub.transaction do
      @book_club.save!
      @book_club.book_club_memberships.create!(user: current_user, role: "owner")
    end
    redirect_to @book_club, notice: "#{@book_club.name} created!"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def join
    authorize @book_club, :join?
    @book_club.book_club_memberships.create!(user: current_user, role: "member")
    redirect_to @book_club, notice: "Joined #{@book_club.name}."
  end

  def leave
    authorize @book_club, :leave?
    current_user.book_club_memberships.find_by!(book_club: @book_club).destroy
    redirect_to book_clubs_path, notice: "You've left #{@book_club.name}."
  end

  def set_current_book
    authorize @book_club, :manage?
    @book_club.update!(current_book_params)
    redirect_to @book_club, notice: "Current pick updated."
  end

  private

  def set_book_club
    @book_club = BookClub.find(params[:id])
  end

  def book_club_params
    params.require(:book_club).permit(:name, :description)
  end

  def current_book_params
    params.require(:book_club).permit(:current_book_id, :reading_deadline)
  end
end
