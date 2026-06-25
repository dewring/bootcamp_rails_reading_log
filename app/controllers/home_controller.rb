class HomeController < ApplicationController
  def index
    books = policy_scope(Book)
    book_most_read = books.most_read.with_attached_cover_image
    @most_read = if params[:genre].present?
      book_most_read.joins(:genres).where(genres: { name: params[:genre] }).limit(8)  # genre 있을 때
    else
      book_most_read.limit(8)  # genre 없을 때
    end
    @new_books = books.with_attached_cover_image.order(created_at: :desc).limit(8)
  end
end
