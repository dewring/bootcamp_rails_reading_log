class Admin::BookClubsController < ApplicationController
  include RequireAuthenticatedAdmin
  include AdminListSorting
  layout "admin"

  SORT_FIELDS = {
    "updated" => [ "Updated", :date ],
    "name" => [ "Club name", :text ],
    "members" => [ "Members", :count ]
  }.freeze
  SORT_COLUMNS = { "updated" => [ :updated_at ], "name" => [ :name ], "members" => [ :book_club_memberships_count ] }.freeze
  before_action :set_book_club, only: [ :update, :destroy ]

  def index
    authorize [ :admin, BookClub ]
    load_workspace
    @is_new_club = params[:new_club].present?
    @detail_club = @is_new_club ? BookClub.new : selected_club
  end

  def search_books
    authorize [ :admin, BookClub ], :index?
    books = policy_scope(Book).matching_club_pick(params[:q]).order(:title, :author, :id).limit(5).pluck(:id, :title, :author)
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
      redirect_to admin_book_clubs_path(club_id: @detail_club.id, q: params[:q].presence, sort: params[:sort].presence, direction: params[:direction].presence, page: params[:page].presence), notice: "Book club updated."
    else
      load_workspace
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    authorize [ :admin, @detail_club ]
    @detail_club.destroy!
    redirect_to admin_book_clubs_path(q: params[:q].presence, sort: params[:sort].presence, direction: params[:direction].presence), notice: "Book club deleted."
  end

  private

  def load_workspace
    @query = params[:q].to_s.strip
    select_admin_list_sort(SORT_FIELDS)
    @club_scope = policy_scope([ :admin, BookClub ]).matching_admin_text(@query)
      .preload(:current_book, book_club_memberships: :user)
    @pagy, @book_clubs = pagy(:offset, @club_scope.order(admin_list_order(SORT_COLUMNS.fetch(@sort))), limit: 4)
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
