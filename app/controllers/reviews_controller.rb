class ReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book
  before_action :set_review, only: [ :edit, :update ]

  def new
    if current_user.reviews.exists?(book: @book)
      redirect_to book_path(@book), alert: "You can review only once per book "
      return
    end
    @review = Review.new
  end
  def create
    if current_user.reviews.exists?(book: @book)
      redirect_to book_path(@book), alert: "You can review only once per book "
      return
    end

    @review = @book.reviews.build(review_params)
    @review.user = current_user

    if @review.save
      redirect_to book_path(@book), notice: "Review added!"
    else
      render :new, status: :unprocessable_entity
    end
  end
  def edit
  end
  def update
    if @review.update(review_params)
      redirect_to book_path(@book), notice: "Review updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def review_params
    params.require(:review).permit(:rating, :body)
  end

  def set_book
    @book = Book.find(params[:book_id])
  end

  def set_review
    @review = @book.reviews.find(params[:id])
  end
end
