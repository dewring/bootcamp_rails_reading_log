class Admin::BooksController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin", only: [ :index ]
  before_action :set_book, only: [ :edit, :update, :destroy ]

  def index
    authorize Book, :index?
    load_catalog
    @is_new_book = params[:new_book].present?
    @selected_book = selected_book
    @selected_book ||= @books.first unless @is_new_book
    @detail_book = @is_new_book ? Book.new : @selected_book
    @detail_book ||= Book.new if @pagy.count.zero?
  end

  def new
    @book = Book.new
    authorize @book
  end
  def create
    @book = Book.new(book_params)
    authorize @book
    if @book.save
      assign_genres
      redirect_to admin_catalog_path(book_id: @book.id), notice: "Book added!"
    else
      load_catalog
      @is_new_book = true
      @detail_book = @book
      render :index, layout: "admin", status: :unprocessable_entity
    end
  end
  def edit
    authorize @book
  end
  def update
    authorize @book
    if @book.update(book_params)
      assign_genres
      redirect_to admin_catalog_path(book_id: @book.id), notice: "Book updated."
    else
      load_catalog
      @selected_book = @book
      @detail_book = @book
      @is_new_book = false
      render :index, layout: "admin", status: :unprocessable_entity
    end
  end
  def destroy
    authorize @book
    @book.destroy
    redirect_to admin_catalog_path, notice: "Book deleted."
  end

  private

  def load_catalog
    books = policy_scope(Book).includes(:genres, :book_editions)
    if params[:q].present?
      query = "%#{Book.sanitize_sql_like(params[:q].to_s.strip)}%"
      books = books.where("books.title ILIKE :query OR books.author ILIKE :query", query: query)
    end
    books = books.joins(:genres).where(genres: { name: params[:genre] }).distinct if params[:genre].present?
    books = books.order(:title, :id)
    @pagy, @books = pagy(:offset, books, limit: 4)
  end

  def selected_book
    return if params[:book_id].blank?

    policy_scope(Book).includes(:genres, :book_editions).find_by(id: params[:book_id])
  end

  def set_book
    @book = Book.find(params[:id])
  end
  def book_params
    params.require(:book).permit(:title, :author, :total_pages, :cover_image)
  end
  def assign_genres
    genre_names = params[:book][:genre_names] || []
    @book.genres = genre_names.reject(&:blank?).map do |name|
      Genre.find_or_create_by!(name: name)
    end
  end
end
