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
    assert_select ".home-trending .trending-total", text: "Total reactions 2", count: 1
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

  test "turning the running switch off restores the original hero and cards even for a treatment actor" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    get root_path
    assert_select ".home-trending-hero", count: 1

    Flipper.disable(:discovery_experiment_running_v1)
    get root_path

    assert_select "h1", text: "Summer Reading Challenge — Join Now"
    assert_select ".home-trending a.book-card", count: 8
    assert_select ".trending-book-card, .home-trending-hero", count: 0
  end

  test "guests receive the original presentation despite enabled experiment flags" do
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)

    get root_path

    assert_response :success
    assert_select ".home-trending a.book-card", count: 8
    assert_select ".trending-book-card, .home-trending-hero", count: 0
  end

  test "a signed in user whose account becomes invited receives the original presentation" do
    sign_in @reader
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)

    @reader.update!(account_status: "invited")
    get root_path

    assert_response :success
    assert_select ".home-trending-hero, .trending-book-card", count: 0
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
      assert_equal "Total reactions 2", first_book.at_css(".trending-total").text.strip
    end
  end

  test "request parameters cannot override the Flipper variant" do
    sign_in @reader

    get root_path, params: { variant: "treatment" }

    assert_select ".home-trending .trending-book-card", count: 8
    assert_select ".home-trending-hero", count: 0
  end
end
