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

  test "the ranking version is reused until invalidation and renewed if its cache entry is lost" do
    version = Book.trending_cache_version
    assert_equal version, Book.trending_cache_version

    Book.expire_trending_cache
    assert_not_equal version, Book.trending_cache_version

    version = Book.trending_cache_version
    Rails.cache.delete(Book::TRENDING_CACHE_VERSION_KEY)
    assert_not_equal version, Book.trending_cache_version
  end

  test "initializing the ranking version cannot replace a concurrent invalidation" do
    original_write = Rails.cache.method(:write)
    committed_version = nil
    interleaved_write = lambda do |name, value, **options|
      if name == Book::TRENDING_CACHE_VERSION_KEY && options[:unless_exist]
        # A commit advances the version after the initial cache miss, before SET NX.
        Book.expire_trending_cache
        committed_version = Rails.cache.read(Book::TRENDING_CACHE_VERSION_KEY)
      end
      original_write.call(name, value, **options)
    end

    version = Rails.cache.stub(:write, interleaved_write) { Book.trending_cache_version }

    assert_not_nil committed_version
    assert_equal committed_version, version
    assert_equal committed_version, Book.trending_cache_version
  end

  test "only committed reaction changes advance the ranking version" do
    version = Book.trending_cache_version
    Reaction.transaction(requires_new: true) do
      @selection.select_kind(kind: "like")
      raise ActiveRecord::Rollback
    end
    assert_equal version, Book.trending_cache_version

    @selection.select_kind(kind: "like")
    assert_not_equal version, Book.trending_cache_version
    version = Book.trending_cache_version
    @selection.select_kind(kind: "like")
    assert_equal version, Book.trending_cache_version
  end

  test "committed book reaction creation change deletion and timestamp refresh invalidate the ranking" do
    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    reaction = @selection.select_kind(kind: "like")
    assert_nil Rails.cache.read(Book::TRENDING_CACHE_KEY)

    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    @selection.select_kind(kind: "love")
    assert_nil Rails.cache.read(Book::TRENDING_CACHE_KEY)

    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    reaction.reload.touch(time: 1.minute.from_now)
    assert_nil Rails.cache.read(Book::TRENDING_CACHE_KEY)

    Rails.cache.write(Book::TRENDING_CACHE_KEY, "cached ranking")
    @selection.clear_selection
    assert_nil Rails.cache.read(Book::TRENDING_CACHE_KEY)
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
