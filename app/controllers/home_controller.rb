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
    prepare_discovery_presentation
  end

  private

  def prepare_discovery_presentation
    response.headers["Cache-Control"] = "no-store"
    @discovery_running = current_user.present? && current_user.reload.account_status == "active" &&
      Flipper.enabled?(:discovery_experiment_running_v1)
    @hero_trending = @discovery_running && @trending_books.any? &&
      Flipper.enabled?(:discovery_hero_trending_v1, current_user)
    @hero_trending_books = @hero_trending ? @trending_books.first(4) : []
    return unless @discovery_running && !@hero_trending

    @trending_reaction_totals = Reaction.eligible.where(book_id: @trending_books.map(&:id)).group(:book_id).count
  end

  def cached_trending_books(books)
    # BookPolicy currently exposes the same public catalog to everyone, so share ranking snapshots.
    # Reapply the policy scope when loading current book attributes and covers.
    ranking = Rails.cache.fetch("home#trending_books/v2", expires_in: TRENDING_CACHE_DURATION) do
      books.trending(as_of: Time.current).limit(8).map do |book|
        { id: book.id, rank: book.trending_rank, reaction_count: book.trending_score }
      end
    end
    visible_books = books.in_order_of(:id, ranking.map { |entry| entry.fetch(:id) }).with_attached_cover_image.to_a
    visible_ids = visible_books.map(&:id)
    @trending_statistics = ranking.select { |entry| visible_ids.include?(entry.fetch(:id)) }.index_by { |entry| entry.fetch(:id) }
    visible_books
  end
end
