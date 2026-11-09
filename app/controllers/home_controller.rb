class HomeController < ApplicationController
  TRENDING_CACHE_DURATION = 30.minutes

  def index
    books = policy_scope(Book)
    book_most_read = books.most_read.includes([ :cover_image_attachment ])
    @most_read = if params[:genre].present?
      book_most_read.joins(:genres).where(genres: { name: params[:genre] }).limit(8)  # genre 있을 때
    else
      book_most_read.limit(8)  # genre 없을 때
    end
    @new_books = books.includes([ :cover_image_attachment ]).order(created_at: :desc).limit(8).to_a
    @featured_book = @new_books.first || @most_read.first
    @trending_books = cached_trending_books(books)
  end

  private

  def cached_trending_books(books)
    # BookPolicy currently exposes the same public catalog to everyone, so share the ranked IDs.
    # Reapply the policy scope when loading current book attributes and covers.
    ids = Rails.cache.fetch("home#trending_books", expires_in: TRENDING_CACHE_DURATION) do
      books.trending(as_of: Time.current).limit(8).map(&:id)
    end
    books.in_order_of(:id, ids).with_attached_cover_image.to_a
  end
end
