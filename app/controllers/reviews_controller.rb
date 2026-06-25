class ReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book
  before_action :set_review, only: [ :edit, :update ]

  def new
    @review = @book.reviews.build(user: current_user)
    unless policy(@review).new?
      redirect_to book_path(@book), alert: "You can review only once per book "
      return
    end

    authorize @review
  end

  def create
    @review = @book.reviews.build(review_params)
    @review.user = current_user

    unless policy(@review).create?
      redirect_to book_path(@book), alert: "You can review only once per book "
      return
    end

    authorize @review

    if @review.save
      redirect_to book_path(@book), notice: "Review added!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @review
  end

  def update
    authorize @review
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
