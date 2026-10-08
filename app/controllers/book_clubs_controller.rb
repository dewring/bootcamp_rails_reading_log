class BookClubsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book_club, only: [ :show, :edit, :update, :join, :leave, :set_current_book, :destroy ]

  def index
    @book_clubs = policy_scope(BookClub)
      .includes(current_book: { cover_image_attachment: :blob }, book_club_memberships: :user)
      .order(created_at: :desc)
  end

  def show
    detail_associations = { book_club_memberships: { user: :avatar_attachment } }
    detail_associations[:current_book] = { cover_image_attachment: :blob }
    @book_club = BookClub
      .includes(detail_associations)
      .find(@book_club.id)
    authorize @book_club
    prepare_detail_state

    if params[:view] == "leaderboard"
      @leaderboard = @book_club.leaderboard.to_a
      return render :leaderboard
    end
  end

  def search_books
    authorize Book, :search?
    books = policy_scope(Book).matching_club_pick(params[:q]).order(:title, :author, :id).limit(5).pluck(:id, :title, :author)
    render json: { books: books.map { |id, title, author| { id: id, title: title, author: author } } }
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

  def edit
    authorize @book_club, :manage?
  end

  def update
    authorize @book_club, :manage?
    if @book_club.update(club_details_params)
      redirect_to @book_club, notice: "Club details updated."
    else
      prepare_detail_state
      render :show, status: :unprocessable_entity
    end
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

  def destroy
    authorize @book_club, :destroy?
    @book_club.destroy!
    redirect_to book_clubs_path, notice: "#{@book_club.name} deleted."
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

  def club_details_params
    params.require(:book_club).permit(:name, :description, :current_book_id, :reading_deadline)
  end

  def prepare_detail_state
    @memberships = if @book_club.book_club_memberships.loaded?
      @book_club.book_club_memberships
    else
      @book_club.book_club_memberships.includes(user: :avatar_attachment)
    end
    @owner = @memberships.find { |membership| membership.role == "owner" }&.user
    @current_membership = @memberships.find { |membership| membership.user_id == current_user.id }
    @past_picks = @book_club.pick_history
  end
end
