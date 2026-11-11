require "test_helper"

class TrendingCacheInvalidationTest < ActiveSupport::TestCase
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @reader = users(:leika)
    @book = books(:refactoring)
    @selection = ReactionSelection.new(user: @reader, target: @book)
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "expiring the ranking deletes its cache entry" do
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")

    Book.expire_trending_cache

    assert_nil Rails.cache.read(Book::TRENDING_CACHE_KEY)
  end

  test "committed book reaction creation change deletion and timestamp refresh preserve the ranking" do
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    reaction = @selection.select_kind(kind: "like")
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)

    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    @selection.select_kind(kind: "love")
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)

    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    reaction.reload.touch(time: 1.minute.from_now)
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)

    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    @selection.clear_selection
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)
  end

  test "same kind retries and absent clears preserve the ranking cache" do
    @selection.select_kind(kind: "like")
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    @selection.select_kind(kind: "like")
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)

    @selection.clear_selection
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    @selection.clear_selection
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)
  end

  test "rolled back creation change and deletion preserve the ranking cache" do
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    Reaction.transaction(requires_new: true) do
      @selection.select_kind(kind: "like")
      raise ActiveRecord::Rollback
    end
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)

    @selection.select_kind(kind: "like")
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    [ -> { @selection.select_kind(kind: "love") }, -> { @selection.clear_selection } ].each do |change|
      Reaction.transaction(requires_new: true) do
        change.call
        raise ActiveRecord::Rollback
      end
      assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)
    end
  end

  test "committed account eligibility changes invalidate the ranking but unrelated updates do not" do
    [ "suspended", "active", "invited" ].each do |status|
      Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
      @reader.update!(account_status: status)
      assert_nil Rails.cache.read(Book::TRENDING_CACHE_KEY)
    end

    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    @reader.update!(account_status: "suspended")
    @reader.update!(first_name: "Renamed")
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)
  end

  test "a rolled back account eligibility change preserves the ranking cache" do
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    User.transaction(requires_new: true) do
      @reader.update!(account_status: "suspended")
      raise ActiveRecord::Rollback
    end
    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)
  end

  test "review reactions do not invalidate the book ranking" do
    review = @book.reviews.create!(user: users(:admin), rating: 4, body: "A review")
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    ReactionSelection.new(user: @reader, target: review).select_kind(kind: "like")

    assert_equal "cached ranking", Rails.cache.read(Book::TRENDING_CACHE_KEY)
  end
end
