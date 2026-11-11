require "test_helper"

class HomeTrendingCacheConcurrencyTest < ActionDispatch::IntegrationTest
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @first = Book.create!(title: "Trending first", author: "Test author")
    @second = Book.create!(title: "Trending second", author: "Test author")
    [ @first, @second ].each do |book|
      Reaction.create!(book: book, user: users(:leika), kind: "like", updated_at: 1.hour.ago)
    end
    Reaction.create!(book: @first, user: users(:jaina), kind: "like", updated_at: 1.hour.ago)
    Reaction.create!(book: @second, user: users(:admin), kind: "like", updated_at: 1.hour.ago)
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "a deletion between ranking calculation and cache write keeps the calculated snapshot until expiry" do
    overlap_ranking_write do
      ReactionSelection.new(user: users(:admin), target: @second).clear_selection
    end

    assert_snapshot_expires_with_current_totals
  end

  test "an eligibility change between ranking calculation and cache write keeps the calculated snapshot until expiry" do
    overlap_ranking_write { users(:admin).update!(account_status: "suspended") }

    assert_snapshot_expires_with_current_totals
  end

  private

  def overlap_ranking_write(&mutation)
    original_fetch = Rails.cache.method(:fetch)
    pending_mutation = mutation
    interleaved_fetch = lambda do |name, **options, &calculation|
      original_fetch.call(name, **options) do
        ranking = calculation.call
        if name == Book::TRENDING_CACHE_KEY && pending_mutation
          # Pause the home request after its SELECT, then commit the other request's
          # mutation before allowing the stale cache write. No thread timing is needed.
          change = pending_mutation
          pending_mutation = nil
          change.call
        end
        ranking
      end
    end
    Rails.cache.stub(:fetch, interleaved_fetch) { get root_path }
  end

  def assert_snapshot_expires_with_current_totals
    get root_path

    assert_response :success
    assert_equal 1, assigns(:trending_statistics).fetch(@second.id).fetch(:rank)
    assert_equal 2, assigns(:trending_statistics).fetch(@second.id).fetch(:reaction_count)
    assert_select ".home-trending .trending-book-card" do |cards|
      card = cards.find { |entry| entry.at_css("a")["href"] == book_path(@second) }
      assert_equal "Total reactions 1", card.at_css(".trending-total").text.strip
    end

    travel 31.minutes do
      get root_path

      assert_response :success
      assert_equal 2, assigns(:trending_statistics).fetch(@second.id).fetch(:rank)
      assert_equal 1, assigns(:trending_statistics).fetch(@second.id).fetch(:reaction_count)
    end
  end
end

# Exercise the same interleavings against the production cache adapter as well.
class HomeTrendingRedisCacheConcurrencyTest < HomeTrendingCacheConcurrencyTest
  setup do
    @redis_cache = ActiveSupport::Cache::RedisCacheStore.new(
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
      namespace: "trending-cache-test-#{SecureRandom.uuid}",
      error_handler: ->(method:, returning:, exception:) { raise exception })
    Rails.cache = @redis_cache
  end

  teardown do
    @redis_cache.clear
  end
end
