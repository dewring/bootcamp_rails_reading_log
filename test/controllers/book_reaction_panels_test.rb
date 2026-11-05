require "test_helper"

class BookReactionPanelsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rack::Attack.reset!
    @book = books(:refactoring)
    @review = reviews(:review1)
    @reader = users(:leika)
    @other = users(:jaina)
  end

  teardown do
    Rack::Attack.reset!
  end

  test "guests see book and review totals without reaction forms or another readers pressed state" do
    @book.reactions.create!(user: @reader, kind: "like")
    @review.reactions.create!(user: @reader, kind: "love")

    get book_path(@book)

    assert_response :success
    assert_select "#reaction_panel_book_#{@book.id} [data-reaction-kind='like']", text: "👍 Like: 1"
    assert_select "#review_#{@review.id} #reaction_panel_review_#{@review.id} [data-reaction-kind='love']", text: "❤️ Love: 1"
    assert_select ".reaction-panel form, .reaction-panel [aria-pressed]", count: 0
    assert_select ".reaction-panel [data-reaction-selection]", text: "No reaction selected", count: 2
  end

  test "readers see only their own independent book and review choices on labelled native buttons" do
    @book.reactions.create!(user: @reader, kind: "like")
    @review.reactions.create!(user: @reader, kind: "love")
    @book.reactions.create!(user: @other, kind: "wow")
    @review.reactions.create!(user: @other, kind: "laugh")
    sign_in @reader

    get book_path(@book)

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "#reaction_panel_book_#{@book.id}" do
      assert_select "form[action='#{book_reaction_path(@book)}'][method='post']", count: 6
      assert_select "button[aria-pressed='true']", text: "👍 Like", count: 1
      assert_select "button[aria-pressed='false']", count: 4
      assert_select "button[type='submit']:not([disabled])", text: "Clear", count: 1
      assert_select "input[name='_method'][value='put']", count: 5
      assert_select "input[name='_method'][value='delete']", count: 1
    end
    assert_select "#reaction_panel_review_#{@review.id} button[aria-pressed='true']", text: "❤️ Love", count: 1

    sign_out @reader
    sign_in @other
    get book_path(@book)

    assert_select "#reaction_panel_book_#{@book.id} button[aria-pressed='true']", text: "😮 Wow", count: 1
    assert_select "#reaction_panel_review_#{@review.id} button[aria-pressed='true']", text: "😂 Laugh", count: 1
  end

  test "native HTML forms select switch and clear without requiring JavaScript" do
    sign_in @reader
    paths = [ book_reaction_path(@book), book_review_reaction_path(@book, @review) ]
    paths.each do |path|
      post path, params: { _method: "put", kind: "like" }
      assert_response :see_other
      follow_redirect!
      assert_response :success
      assert_select "form[action='#{path}'] button[aria-pressed='true']", text: "👍 Like"

      post path, params: { _method: "put", kind: "love" }
      assert_response :see_other
      follow_redirect!
      assert_select "form[action='#{path}'] button[aria-pressed='true']", text: "❤️ Love"

      post path, params: { _method: "delete" }
      assert_response :see_other
      follow_redirect!
      assert_select "form[action='#{path}'] button[aria-pressed='true']", count: 0
      assert_select "form[action='#{path}'] button[disabled]", text: "Clear"
    end
  end

  test "invited readers see counts without selectable controls" do
    @reader.update!(account_status: "invited")
    sign_in @reader

    get book_path(@book)

    assert_response :success
    assert_select ".reaction-panel", count: 2
    assert_select ".reaction-panel form", count: 0
  end

  test "disabled selections remain visible and clearable while unused disabled kinds stay hidden" do
    @book.reactions.create!(user: @reader, kind: "like")
    reaction_types(:like).update!(enabled: false)
    reaction_types(:wow).update!(enabled: false)
    sign_in @reader

    get book_path(@book)

    assert_select "#reaction_panel_book_#{@book.id}" do
      assert_select "[data-reaction-kind='like']", text: "👍 Like: 1"
      assert_select "button[aria-pressed='true'][disabled]", text: "👍 Like"
      assert_select "button:not([disabled])", text: "Clear"
      assert_select "[data-reaction-kind='wow']", count: 0
    end
    assert_select "#reaction_panel_review_#{@review.id} [data-reaction-kind='like']", count: 0
  end

  test "adding and relabelling catalog choices updates buttons without changing reaction timestamps" do
    type = ReactionType.create!(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: true)
    reaction = @review.reactions.create!(user: @reader, kind: type.key)
    before = reaction.attributes
    type.update!(label: "Celebration", emoji: "🙌🏽")
    sign_in @reader

    get book_path(@book)

    assert_select "#reaction_panel_book_#{@book.id} button[aria-pressed='false']", text: "🙌🏽 Celebration"
    assert_select "#reaction_panel_review_#{@review.id} button[aria-pressed='true']", text: "🙌🏽 Celebration"
    assert_select "#reaction_panel_review_#{@review.id} [data-reaction-kind='celebrate']", text: "🙌🏽 Celebration: 1"
    assert_equal before, reaction.reload.attributes
  end

  test "review totals and viewer choices use two batched queries as the review list grows" do
    sign_in @reader
    @review.reactions.create!(user: @reader, kind: "love")
    first_queries = review_reaction_queries { get book_path(@book) }
    [ @other, users(:admin) ].each do |author|
      review = @book.reviews.create!(user: author, rating: 4, body: "Another reflection")
      review.reactions.create!(user: @reader, kind: "wow")
    end

    second_queries = review_reaction_queries { get book_path(@book) }

    assert_response :success
    assert_equal 2, first_queries.length
    assert_equal 2, second_queries.length
    assert_select ".book-detail-review-card .reaction-panel", count: 3
    assert_select ".book-detail-review-card button[aria-pressed='true']", count: 3
  end

  private

  def review_reaction_queries
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      sql = payload.fetch(:sql)
      queries.push(sql) if sql.match?(/\ASELECT\b.*\bFROM "review_reactions"/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
