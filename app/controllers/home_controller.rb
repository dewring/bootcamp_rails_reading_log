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
    @book_of_the_day = book_of_the_day(books)
    @trending_books = cached_trending_books(books)
    prepare_discovery_presentation
  end

  private

  # Every reader sees the same pick for the whole day, so the banner stays put
  # across reloads and changes once a day. Books with a cover and a description
  # come first so the banner has artwork and copy to show.
  def book_of_the_day(books)
    showcase = books.joins(:cover_image_attachment).where.not(description: [ nil, "" ])
    candidates = showcase.exists? ? showcase : books
    count = candidates.count
    return if count.zero?

    candidates.order(:id).offset(Date.current.jd % count).first
  end

  def prepare_discovery_presentation
    # The layout depends on the reader and current flags; do not reuse HTTP-cached HTML.
    response.headers["Cache-Control"] = "no-store"
    @hero_trending = hero_trending_for_current_user?
    if @hero_trending
      @hero_trending_books = @trending_books.first(4)
    else
      prepare_trending_reaction_summary
    end
  end

  def prepare_trending_reaction_summary
    types = ReactionType.all.index_by(&:key)
    counts = @trending_reaction_counts
    @trending_reaction_emojis = counts.keys.group_by(&:first).transform_values do |keys|
      keys.first(3).map { |_book_id, kind| types.fetch(kind) }
    end
    @trending_reaction_totals = counts.each_with_object(Hash.new(0)) do |((book_id, _kind), count), totals|
      totals[book_id] += count
    end
  end

  # Flags never replace authorization: only signed-in active readers enter the comparison.
  def hero_trending_for_current_user?
    return false unless current_user&.account_status == "active"
    return false unless Flipper.enabled?(:discovery_experiment_running_v1)
    return false if @trending_books.empty?

    Flipper.enabled?(:discovery_hero_trending_v1, current_user)
  end

  def cached_trending_books(books)
    # BookPolicy currently exposes the same public catalog to everyone, so share ranking snapshots.
    # Reapply the policy scope when loading current book attributes and covers.
    snapshot = Rails.cache.fetch(Book::TRENDING_CACHE_KEY, expires_in: TRENDING_CACHE_DURATION) do
      trending_snapshot(books)
    end
    ranking = snapshot.fetch(:ranking)
    # HTML needs cover metadata and variant records to generate URLs. The image
    # request loads processed variant attachments separately, so omit those here.
    visible_books = books.in_order_of(:id, ranking.map { |entry| entry.fetch(:id) })
      .includes(cover_image_attachment: { blob: :variant_records }).to_a
    visible_ids = visible_books.map(&:id)
    @trending_statistics = ranking.select { |entry| visible_ids.include?(entry.fetch(:id)) }.index_by { |entry| entry.fetch(:id) }
    @trending_reaction_counts = snapshot.fetch(:reaction_counts).select do |(book_id, _kind), _count|
      visible_ids.include?(book_id)
    end
    visible_books
  end

  def trending_snapshot(books)
    ranking = books.trending(as_of: Time.current).limit(8).map do |book|
      { id: book.id, rank: book.trending_rank, reaction_count: book.trending_score }
    end
    # Keep the all-time summary and seven-day ranking in one cache entry so
    # both layouts share the same expiry, even when the hero fills it first.
    reaction_counts = Reaction.eligible.where(book_id: ranking.map { |entry| entry.fetch(:id) })
      .group(:book_id, :kind).order(Arel.sql("MAX(reactions.updated_at) DESC"), :kind).count

    { ranking: ranking, reaction_counts: reaction_counts }
  end
end
