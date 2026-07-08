class BooksController < ApplicationController
  SORTABLE_COLUMNS = %w[title author total_pages].freeze

  before_action :authenticate_user!, only: [ :discover, :most_recent_session, :search, :import ]
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  before_action :set_book, only: [ :show, :most_recent_session ]

  def index
    authorize Book
    books = policy_scope(Book)
    @books = if params[:q].present?
      books.left_joins(:book_editions)
     .where(
       "books.title LIKE :q OR books.author LIKE :q OR book_editions.title LIKE :q",
       q: "%#{params[:q]}%"
     )
     .distinct
    else
      books.includes(:genres)
    end
    @books = @books.joins(:genres).where(genres: { name: params[:genre] }) if params[:genre].present?
    sort_col = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : "title"
    @books = @books.order(sort_col)
    @pagy, @books = pagy(:offset, @books, limit: 10)

    respond_to do |format|
      format.html do
        @books = @books.includes([ :cover_image_attachment ]).to_a
      end
      format.json do
        render json: {
          pagination: @pagy.data_hash,
          books: @books.as_json(include: :genres)
        }
      end
    end
  end

  def show
    authorize @book

    @book_editions = Rails.cache.fetch("book:#{@book.id}:editions:list", expires_in: 1.day) do
      @book.book_editions.includes(:cover_image_attachment).to_a
    end
    @reviews = policy_scope(@book.reviews).includes(:user).order(created_at: :desc)
  end

  def most_recent_session
    authorize @book, :most_recent_session?
    @reading_session = policy_scope(@book.reading_sessions).order(read_on: :desc).first
    if @reading_session
      redirect_to dashboard_path
    else
      redirect_to book_path(@book), alert: "No reading sessions yet."
    end
  end

  def import
    authorize Book, :import?
    doc = {
      "key"         => params[:ol_work_key],
      "title"       => params[:title],
      "author_name" => [ params[:author] ]
    }
    book = Book.find_or_create_from_search_result(doc)
    BookMirrorJob.perform_later(book)
    redirect_to book_path(book), notice: "Book added! Editions are loading in the background."
  end

  def search
    authorize Book, :search?
    @query = params[:q].to_s.strip
    @results = @query.present? ? OpenLibraryClient.new.search(@query) : []
  end

  def discover
    authorize Book, :discover?
    read_book_ids = current_user.books.pluck(:id)
    if @book = policy_scope(Book).where.not(id: read_book_ids).order("RANDOM()").first
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
