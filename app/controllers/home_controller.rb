class HomeController < ApplicationController
  def index
    @most_read = if params[:genre].present?
      Book.most_read.joins(:genres).where(genres: { name: params[:genre] }).limit(8)  # genre 있을 때
    else
      Book.most_read.limit(8)  # genre 없을 때
    end
    @new_books = Book.order(created_at: :desc).limit(8)
  end
end
