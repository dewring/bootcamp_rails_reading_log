class Admin::BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: [ :edit, :update, :destroy ]

  def new
    @book = Book.new
    authorize @book
  end
  def create
    @book = Book.new(book_params)
    authorize @book
    if @book.save
      assign_genres
      redirect_to book_path(@book), notice: "Book added!"
    else
      render :new, status: :unprocessable_entity
    end
  end
  def edit
    authorize @book
  end
  def update
    authorize @book
    if @book.update(book_params)
      assign_genres
      redirect_to book_path(@book), notice: "Book updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
  def destroy
    authorize @book
    @book.destroy
    redirect_to books_path, notice: "Books deleted."
  end

  private
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
