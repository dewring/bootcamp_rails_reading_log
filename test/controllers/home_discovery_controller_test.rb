require "test_helper"

class HomeDiscoveryControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @reader = users(:leika)
    @books = 9.times.map do |index|
      book = Book.create!(title: "Discovery book #{index}", author: "Discovery author")
      Reaction.create!(user: users(:jaina), book: book, kind: "like", updated_at: (index + 1).hours.ago)
      book
    end
    Reaction.create!(user: users(:admin), book: @books.last, kind: "love", updated_at: 1.hour.ago)
    @ranked_books = [ @books.last, *@books.first(7) ]
    Flipper.add(:discovery_experiment_running_v1)
    Flipper.add(:discovery_hero_trending_v1)
    Flipper.enable(:discovery_experiment_running_v1)
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "control keeps the challenge hero and eight ranked cards with aggregate reaction totals" do
    sign_in @reader

    get root_path

    assert_response :success
    assert_select "h1", text: "Summer Reading Challenge — Join Now"
    assert_select ".home-trending .trending-book-card", count: 8
    assert_select ".home-trending .trending-total", count: 8
    assert_select ".home-trending .trending-rank[aria-label='Rank 1']", count: 1
    assert_select ".home-trending .trending-rank[aria-label='Rank 2']", count: 7
    assert_select ".home-trending .trending-total[aria-label='Total reactions 2']", count: 1
    assert_select ".home-trending .book-card" do |links|
      assert_equal @ranked_books.map { |book| book_path(book) }, links.map { |link| link["href"] }
    end
  end

  test "treatment replaces the hero with the first four ranked book links and omits the separate shelf and counts" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)

    get root_path

    assert_response :success
    assert_select "h1#home-hero-title", text: "New & Trending"
    assert_select ".home-trending-hero .trending-book-card", count: 4
    assert_select ".home-trending-hero .trending-rank", count: 4
    assert_select ".home-trending, .home-trending-hero .trending-total", count: 0
    assert_select ".home-trending-hero .book-card" do |links|
      assert_equal @ranked_books.first(4).map { |book| book_path(book) }, links.map { |link| link["href"] }
    end
    assert_select "h2", text: "Most Read"
    assert_select "h2", text: "New Books"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "turning the running switch off restores the default hero and ranked cards even for a treatment actor" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    get root_path
    assert_select ".home-trending-hero", count: 1

    Flipper.disable(:discovery_experiment_running_v1)
    get root_path

    assert_select "h1", text: "Summer Reading Challenge — Join Now"
    assert_select ".home-trending a.book-card", count: 8
    assert_select ".home-trending .trending-rank, .home-trending .trending-total", count: 16
    assert_select ".home-trending-hero", count: 0
  end

  test "guests receive the default ranked presentation despite enabled experiment flags" do
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)

    get root_path

    assert_response :success
    assert_select ".home-trending a.book-card", count: 8
    assert_select ".home-trending .trending-rank, .home-trending .trending-total", count: 16
    assert_select ".home-trending-hero", count: 0
  end

  test "a signed in user whose account becomes invited receives the default ranked presentation" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)

    @reader.update!(account_status: "invited")
    get root_path

    assert_response :success
    assert_select ".home-trending-hero", count: 0
    assert_select ".home-trending .trending-rank, .home-trending .trending-total", count: 16
    assert_select "h1", text: "Summer Reading Challenge — Join Now"
  end

  test "a suspended signed in user retains the existing Devise sign in redirect" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    @reader.update!(account_status: "suspended")

    get root_path

    assert_redirected_to new_user_session_path
  end

  test "an empty ranking preserves the challenge hero and empty Trending state" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    Reaction.delete_all

    get root_path

    assert_select "h1", text: "Summer Reading Challenge — Join Now"
    assert_select ".home-trending .empty-state", count: 1
    assert_select ".home-trending-hero", count: 0
  end

  test "treatment displays only available books when fewer than four qualify" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    Reaction.where.not(book: @books.first(2)).delete_all

    get root_path

    assert_select ".home-trending-hero .book-card", count: 2
    assert_select ".home-trending", count: 0
  end

  test "control totals include old reactions across emoji types without changing the cached seven day rank" do
    sign_in @reader
    Reaction.create!(user: users(:admin), book: @books.first, kind: "dislike", updated_at: 8.days.ago)

    get root_path

    assert_select ".home-trending .trending-book-card" do |cards|
      first_book = cards.find { |card| card.at_css("a")["href"] == book_path(@books.first) }
      assert_equal "Rank 2", first_book.at_css(".trending-rank")["aria-label"]
      assert_equal "Total reactions 2", first_book.at_css(".trending-total")["aria-label"]
    end
  end

  test "control badges show the three most recently received distinct emoji and count all eligible reactions" do
    ReactionType.create!(key: "sad", label: "Sad", emoji: "😢", enabled: true)
    book = @books.first
    types = [ "like", "dislike", "love", "laugh", "wow", "sad" ].map { |kind| ReactionType.find_by!(key: kind) }
    types.each_with_index do |type, index|
      reader = User.create!(first_name: "Badge", last_name: "Reader", nickname: "badge-reader-#{index}",
        email: "badge-reader-#{index}@example.com", password: "password123")
      Reaction.create!(user: reader, book: book, kind: type.key, updated_at: 8.days.ago + index.hours)
    end
    # Disabled types still describe historical reactions already present.
    ReactionType.find_by!(key: "sad").update!(enabled: false)
    Reaction.create!(user: users(:admin), book: book, kind: "wow")
    users(:admin).update!(account_status: "suspended")

    get root_path

    assert_response :success
    assert_select ".trending-book-card:has(a[href='#{book_path(book)}'])" do
      assert_select ".trending-total[aria-label='Total reactions 7']", count: 1
      assert_select ".trending-reaction-count", text: "7"
      assert_select ".trending-reaction-emojis[aria-hidden='true'] > span" do |emoji|
        assert_equal [ "like", "sad", "wow" ], emoji.map { |node| node["data-reaction-kind"] }
        assert_equal [ "👍", "😢", "😮" ], emoji.map(&:text)
        assert_equal 3, emoji.size
      end
      assert_select ".trending-total button, .trending-total a", count: 0
    end
  end

  test "changing a reaction moves its new kind first without repeating kinds or refreshing the ranking" do
    book = @books.first
    reaction = Reaction.create!(user: users(:admin), book: book, kind: "love", updated_at: 2.hours.ago)
    get root_path
    cached_ranking = Rails.cache.read(Book::TRENDING_CACHE_KEY)

    reaction.update!(kind: "wow")
    get root_path

    assert_equal cached_ranking, Rails.cache.read(Book::TRENDING_CACHE_KEY)
    assert_select ".trending-book-card:has(a[href='#{book_path(book)}'])" do
      assert_select ".trending-reaction-emojis > span" do |emoji|
        assert_equal [ "wow", "like" ], emoji.map { |node| node["data-reaction-kind"] }
      end
      assert_select ".trending-reaction-count", text: "2"
    end
  end

  test "a cached book with no remaining reactions shows zero without emoji" do
    get root_path
    book = @books.first
    book.reactions.destroy_all

    get root_path

    assert_select ".trending-book-card:has(a[href='#{book_path(book)}'])" do
      assert_select ".trending-total[aria-label='Total reactions 0']", count: 1
      assert_select ".trending-reaction-count", text: "0"
      assert_select "[data-reaction-kind]", count: 0
    end
  end

  test "request parameters cannot override the Flipper variant" do
    sign_in @reader

    get root_path, params: { variant: "treatment" }

    assert_select ".home-trending .trending-book-card", count: 8
    assert_select ".home-trending-hero", count: 0
  end

  test "a fifty percent actor gate preserves the same home presentation across repeated requests" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 50)
    treatment = Flipper.enabled?(:discovery_hero_trending_v1, @reader)

    3.times do
      get root_path

      assert_response :success
      assert_select ".home-trending-hero", count: treatment ? 1 : 0
      assert_select ".home-trending", count: treatment ? 0 : 1
    end
    assert_equal 50, Flipper[:discovery_hero_trending_v1].percentage_of_actors_value
  end

  test "a persisted account status change is read on the next request without reusing the signed in user object" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    get root_path
    assert_select ".home-trending-hero", count: 1

    User.find(@reader.id).update!(account_status: "invited")
    assert_equal "active", @reader.account_status
    get root_path

    assert_response :success
    assert_select ".home-trending-hero", count: 0
    assert_select ".home-trending .trending-book-card", count: 8
  end

  test "both home presentations disable HTTP caching and Turbo snapshot caching" do
    sign_in @reader

    [ 0, 100 ].each do |percentage|
      Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, percentage)
      get root_path

      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select "head meta[name='turbo-cache-control'][content='no-cache']", count: 1
    end
  end
end
