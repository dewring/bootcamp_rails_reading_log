class Admin::BookClubsController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin"
  before_action :set_book_club, only: [ :update, :destroy ]

  def index
    authorize [ :admin, BookClub ]
    load_workspace
    @is_new_club = params[:new_club].present?
    @detail_club = @is_new_club ? BookClub.new : selected_club
  end

  def search_books
    authorize [ :admin, BookClub ]
    query = params[:q].to_s.strip
    books = if query.present?
      policy_scope(Book).where("title ILIKE :query OR author ILIKE :query", query: "%#{Book.sanitize_sql_like(query)}%")
        .order(:title, :author, :id).limit(10).pluck(:id, :title, :author)
    else
      []
    end
    render json: { books: books.map { |id, title, author| { id: id, title: title, author: author } } }
  end

  def create
    @detail_club = BookClub.new(book_club_params)
    authorize [ :admin, @detail_club ]
    BookClubCreator.new(book_club: @detail_club, owner: current_user).create_club
    redirect_to admin_book_clubs_path(club_id: @detail_club.id), notice: "Book club created."
  rescue ActiveRecord::RecordInvalid
    @is_new_club = true
    load_workspace
    render :index, status: :unprocessable_entity
  end

  def update
    authorize [ :admin, @detail_club ]
    if @detail_club.update(book_club_params)
      redirect_to admin_book_clubs_path(club_id: @detail_club.id, q: params[:q].presence, sort: params[:sort].presence, page: params[:page].presence), notice: "Book club updated."
    else
      load_workspace
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    authorize [ :admin, @detail_club ]
    @detail_club.destroy!
    redirect_to admin_book_clubs_path(q: params[:q].presence, sort: params[:sort].presence), notice: "Book club deleted."
  end

  private

  def load_workspace
    @query = params[:q].to_s.strip
    @sort = params[:sort] == "name" ? "name" : "updated"
    @club_scope = policy_scope([ :admin, BookClub ]).matching_admin_text(@query)
      .preload(:current_book, book_club_memberships: :user)
    order = @sort == "name" ? { name: :asc, id: :asc } : { updated_at: :desc, id: :desc }
    @pagy, @book_clubs = pagy(:offset, @club_scope.order(order), limit: 4)
  end

  def selected_club
    @club_scope.find_by(id: params[:club_id]) || @book_clubs.first
  end

  def set_book_club
    @detail_club = policy_scope([ :admin, BookClub ]).find(params[:id])
  end

  def book_club_params
    params.require(:book_club).permit(:name, :description, :current_book_id, :reading_deadline)
  end
end
