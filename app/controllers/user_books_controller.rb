class UserBooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user_book, only: [ :update, :destroy ]

  def new
    @book = Book.find(params[:book_id])
    @user_book = current_user.user_books.new(book: @book)
    unless policy(@user_book).new?
      redirect_to @book, notice: "This book is already in your reading log."
      return
    end

    authorize @user_book
  end

  def create
    @book = Book.find(params[:user_book][:book_id])
    @user_book = current_user.user_books.new(user_book_params)
    unless policy(@user_book).create?
      redirect_to @book, notice: "This book is already in your reading log."
      return
    end

    authorize @user_book

    if @user_book.save
      redirect_to dashboard_path, notice: "#{@book.title} added to your reading log."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    authorize @user_book
    if @user_book.update(user_book_params)
      redirect_to dashboard_path, notice: "Status updated."
    else
      redirect_to dashboard_path, alert: "Could not update status."
    end
  end

  def destroy
    authorize @user_book
    @user_book.destroy
    redirect_to dashboard_path, notice: "Book removed from your log."
  end

  private

  def set_user_book
    @user_book = UserBook.find(params[:id])
  end

  def user_book_params
    params.require(:user_book).permit(:book_id, :status)
  end
end
