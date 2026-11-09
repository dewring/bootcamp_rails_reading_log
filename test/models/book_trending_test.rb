require "test_helper"

class BookTrendingTest < ActiveSupport::TestCase
  setup do
    @as_of = Time.zone.local(2026, 11, 9, 12)
    @first = Book.create!(title: "First trending book", author: "Test author")
    @second = Book.create!(title: "Second trending book", author: "Test author")
    @third = Book.create!(title: "Third trending book", author: "Test author")
    @candidates = Book.where(id: [ @first.id, @second.id, @third.id ])
  end

  test "all reaction kinds contribute equally and zero-score books are excluded" do
    add_reaction(@first, :leika, "dislike")
    add_reaction(@first, :jaina, "love")
    add_reaction(@second, :leika, "laugh")

    rows = ranked_books

    assert_equal [ @first.id, @second.id ], rows.map(&:id)
    assert_equal [ 2, 1 ], rows.map(&:trending_score)
    assert_equal [ 1, 2 ], rows.map(&:trending_rank)
  end

  test "equal scores share ranks with gaps while recency orders tied cards" do
    add_reaction(@first, :leika, "like", at: @as_of - 2.days)
    add_reaction(@first, :jaina, "dislike", at: @as_of - 2.days)
    add_reaction(@second, :leika, "love")
    add_reaction(@second, :jaina, "laugh")
    add_reaction(@third, :leika, "wow")

    rows = ranked_books

    assert_equal [ @second.id, @first.id, @third.id ], rows.map(&:id)
    assert_equal [ 1, 1, 3 ], rows.map(&:trending_rank)
    assert_equal [ @second.id ], @candidates.trending(as_of: @as_of).limit(1).map(&:id)
  end

  test "equal scores and reaction times are ordered by book ID" do
    add_reaction(@second, :leika, "like")
    add_reaction(@first, :leika, "dislike")

    assert_equal [ @first.id, @second.id ], ranked_books.map(&:id)
    assert_equal [ 1, 1 ], ranked_books.map(&:trending_rank)
  end

  test "the lower time boundary is included and the upper and older boundaries are excluded" do
    add_reaction(@first, :leika, "like", at: @as_of - 7.days)
    add_reaction(@second, :leika, "like", at: @as_of)
    add_reaction(@third, :leika, "like", at: @as_of - 7.days - 1.second)

    assert_equal [ @first.id ], ranked_books.map(&:id)
  end

  test "the seven-day window follows calendar days across daylight saving time" do
    Time.use_zone("America/New_York") do
      @as_of = Time.zone.local(2026, 11, 2, 12)
      lower_bound = Time.zone.local(2026, 10, 26, 12)
      add_reaction(@first, :leika, "like", at: lower_bound)
      add_reaction(@second, :leika, "dislike", at: lower_bound - 1.second)

      assert_equal 169.hours, @as_of - lower_bound
      assert_equal [ @first.id ], ranked_books.map(&:id)
    end
  end

  test "inactive and deleted users do not contribute" do
    add_reaction(@first, :leika, "like")
    add_reaction(@second, :jaina, "dislike")
    users(:leika).update!(account_status: "suspended")
    users(:jaina).destroy!

    assert_empty ranked_books
  end

  test "same-kind repeats preserve recency while switching renews one contribution and clearing removes it" do
    reaction = add_reaction(@first, :leika, "like", at: @as_of - 10.days)
    selection = ReactionSelection.new(user: users(:leika), target: @first)

    travel_to(@as_of - 1.hour) do
      selection.select_kind(kind: "like")
      assert_equal @as_of - 10.days, reaction.reload.updated_at
      assert_empty ranked_books

      selection.select_kind(kind: "dislike")
      assert_equal [ 1 ], ranked_books.map(&:trending_score)

      selection.clear_selection
      assert_empty ranked_books
    end
  end

  test "a restricted candidate relation is ranked without excluded books" do
    add_reaction(@first, :leika, "like")
    add_reaction(@first, :jaina, "like")
    add_reaction(@second, :leika, "dislike")

    rows = Book.where(id: @second.id).trending(as_of: @as_of).to_a

    assert_equal [ @second.id ], rows.map(&:id)
    assert_equal [ 1 ], rows.map(&:trending_rank)
  end

  test "no reactions produces no candidates" do
    assert_empty ranked_books
  end

  private

  def add_reaction(book, user, kind, at: @as_of - 1.day)
    Reaction.create!(book: book, user: users(user), kind: kind, created_at: at, updated_at: at)
  end

  def ranked_books
    @candidates.trending(as_of: @as_of).to_a
  end
end
