class BooksController < ApplicationController
  SORTABLE_COLUMNS = %w[title author total_pages].freeze

  before_action :authenticate_user!, only: [ :discover ]
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  before_action :set_book, only: [ :show, :most_recent_session ]

  def index
    book = policy_scope(Book).with_attached_cover_image
    @books = if params[:q].present?
      book.search(title: params[:q], author: params[:q]).includes(:genres)
    else
      book.includes(:genres)
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
    authorize @book
    @reviews = @book.reviews.includes(:user).order(created_at: :desc)
  end
  def most_recent_session
    @reading_session = @book.reading_sessions.order(read_on: :desc).first
    if @reading_session
      redirect_to dashboard_path
    else
      redirect_to book_path(@book), alert: "No reading sessions yet."
    end
  end
  def discover
    read_book_ids = current_user.books.pluck(:id)
    if @book = Book.where.not(id: read_book_ids).order("RANDOM()").first
      redirect_to book_path(@book)
    else
      redirect_to root_path, alert: "You've read everything! Add more books."
    end
  end

  private
  def set_book
    @book = Book.find(params[:id])
  end
  def not_found
    render json: { error: "Not found" }, status: :not_found
  end
end
