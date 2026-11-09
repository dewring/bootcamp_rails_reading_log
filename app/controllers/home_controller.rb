class HomeController < ApplicationController
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
    load_trending_books(books)
  end

  private

  def load_trending_books(books)
    @trending_as_of = Time.current
    @trending_books = books.trending(as_of: @trending_as_of).with_attached_cover_image.limit(8).to_a
    @trending_reaction_types = ReactionType.order(:id).to_a
    @trending_reaction_counts = Reaction.eligible.where(book_id: @trending_books.map(&:id)).group(:book_id, :kind).count
  end
end
