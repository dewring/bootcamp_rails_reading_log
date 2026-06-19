class UserBooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user_book, only: [ :update, :destroy ]

  def new
    @book = Book.find(params[:book_id])
    if current_user.user_books.exists?(book: @book)
      redirect_to @book, notice: "This book is already in your reading log."
      return
    end
    @user_book = UserBook.new
  end

  def create
    @book = Book.find(params[:user_book][:book_id])
    @user_book = current_user.user_books.new(user_book_params)

    if @user_book.save
      redirect_to dashboard_path, notice: "#{@book.title} added to your reading log."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @user_book.update(user_book_params)
      redirect_to dashboard_path, notice: "Status updated."
    else
      redirect_to dashboard_path, alert: "Could not update status."
    end
  end

  def destroy
    @user_book.destroy
    redirect_to dashboard_path, notice: "Book removed from your log."
  end

  private

  def set_user_book
    @user_book = current_user.user_books.find(params[:id])
  end

  def user_book_params
    params.require(:user_book).permit(:book_id, :status)
  end
end
