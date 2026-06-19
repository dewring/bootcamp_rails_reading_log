class BooksController < ApplicationController
  SORTABLE_COLUMNS = %w[title author total_pages].freeze
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :require_admin!, except: [ :index, :show ]
  before_action :set_book, only: [ :show, :edit, :update, :destroy ]

  def index
    @books = if params[:q].present?
      Book.search(title: params[:q], author: params[:q]).includes(:genres)
    else
      Book.includes(:genres)
    end
    @books = @books.joins(:genres).where(genres: { name: params[:genre] }) if params[:genre].present?
    sort_col = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : "title"
    @books = @books.order(sort_col)
    respond_to do |format|
      format.html
      format.json { render json: @books, include: :genres }
    end
  end

  def show
    @reviews = @book.reviews.includes(:user).order(created_at: :desc)
  end

  def new
    @book = Book.new
  end

  def create
    @book = Book.new(book_params)
    if @book.save
      assign_genres  # ← after save
      redirect_to @book, notice: "Book added to catalog."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
      assign_genres  # ← after update
      redirect_to @book, notice: "Book updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @book.destroy
    redirect_to books_path, notice: "Book removed from catalog."
  end

  private

  def set_book
    @book = Book.find(params[:id])
  end

  def book_params
    params.require(:book).permit(:title, :author, :total_pages, :cover_image)
  end

  def not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def require_admin!
    unless current_user&.admin?
      if request.format.json?
        render json: { error: "Forbidden" }, status: :forbidden
      else
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end

  def assign_genres
    genre_names = params[:book][:genre_names] || []
    @book.genres = genre_names.reject(&:blank?).map do |name|
      Genre.find_or_create_by!(name: name)
    end
  end
end
