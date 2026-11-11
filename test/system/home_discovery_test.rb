require "application_system_test_case"

class HomeDiscoveryTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Warden.test_mode!
    login_as users(:leika), scope: :user
    @books = 8.times.map do |index|
      book = Book.create!(title: index.zero? ? "A Longer Trending Book Title" : "Book #{index}", author: "Test author")
      book.reactions.create!(user: users(:leika), kind: "like", updated_at: (index + 1).hours.ago)
      book
    end
    Flipper.add(:discovery_experiment_running_v1)
    Flipper.add(:discovery_hero_trending_v1)
    Flipper.enable(:discovery_experiment_running_v1)
  end

  teardown do
    Warden.test_reset!
    Rails.cache = @previous_cache
    page.current_window.resize_to(1400, 1000)
  end

  test "control reaction totals align while authors follow their titles" do
    visit root_path

    assert_selector ".home-trending .trending-total", count: 8
    positions = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('.home-trending .trending-total'))
        .map(element => element.getBoundingClientRect().top)
    JS
    assert_operator positions.max - positions.min, :<=, 1
    assert page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('.home-trending .trending-book-card')).every(card => {
        const title = card.querySelector('.book-title').getBoundingClientRect()
        const author = card.querySelector('.book-author').getBoundingClientRect()
        return author.top - title.bottom < 5
      })
    JS
    page.save_screenshot(File.join(Capybara.save_path, "issue145-control-desktop.png"))
  end

  test "three recent emoji and the total across six kinds fit on desktop and mobile" do
    ReactionType.create!(key: "sad", label: "Sad", emoji: "😢", enabled: true)
    types = ReactionType.order(:id).to_a
    types.each_with_index do |type, index|
      reader = User.create!(first_name: "Badge", last_name: "Reader", nickname: "badge-reader-#{index}",
        email: "badge-reader-#{index}@example.com", password: "password123")
      @books.first.reactions.create!(user: reader, kind: type.key, updated_at: 1.hour.ago)
    end

    [ [ 1400, 1000 ], [ 390, 844 ] ].each do |width, height|
      page.current_window.resize_to(width, height)
      visit root_path
      within ".home-trending .trending-book-card:first-child" do
        assert_selector ".trending-total[aria-label='Total reactions 7']"
        assert_selector ".trending-reaction-emojis > span", count: 3
      end
      # Exercise wrapping with a count wider than this fixture's total.
      page.execute_script("document.querySelector('.trending-reaction-count').textContent = '123456'")
      assert page.evaluate_script(<<~JS)
        (() => {
          const card = document.querySelector('.home-trending .trending-book-card')
          const badge = card.querySelector('.trending-total')
          const bounds = badge.getBoundingClientRect()
          const cardBounds = card.getBoundingClientRect()
          return bounds.left >= cardBounds.left - 1 && bounds.right <= cardBounds.right + 1 &&
            Array.from(badge.querySelectorAll('[data-reaction-kind], .trending-reaction-count')).every(node => {
              const rect = node.getBoundingClientRect()
              return rect.left >= bounds.left && rect.right <= bounds.right &&
                rect.top >= bounds.top && rect.bottom <= bounds.bottom
            })
        })()
      JS
      page.execute_script(<<~JS)
        document.querySelector('.trending-reaction-count').textContent = '7'
        document.querySelector('.home-trending').scrollIntoView()
      JS
      page.save_screenshot(File.join(Capybara.save_path, "reaction-summary-#{width}.png"))
    end
  end

  test "treatment books stack without horizontal overflow on mobile and open real book detail pages" do
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    visit root_path

    assert_selector ".home-trending-hero .book-card", count: 4
    assert_no_selector ".home-trending, .home-trending-hero .trending-total"
    page.save_screenshot(File.join(Capybara.save_path, "issue145-treatment-desktop.png"))
    page.current_window.resize_to(390, 844)
    assert page.evaluate_script(<<~JS)
      (() => {
        const hero = document.querySelector('.home-trending-hero').getBoundingClientRect()
        const cards = Array.from(document.querySelectorAll('.trending-hero-books .book-card'))
          .map(card => card.getBoundingClientRect())
        return hero.left >= 0 && hero.right <= window.innerWidth &&
          cards.every((card, index) => card.left >= hero.left && card.right <= hero.right &&
          (index === 0 || card.top > cards[index - 1].bottom))
      })()
    JS
    page.save_screenshot(File.join(Capybara.save_path, "issue145-treatment-mobile.png"))
    within ".home-trending-hero" do
      click_link @books.first.title
    end
    assert_current_path book_path(@books.first)
  end

  test "both presentations allow keyboard users to tab to a trending book and open it with Enter" do
    [ 0, 100 ].each do |percentage|
      Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, percentage)
      visit root_path
      selector = percentage.zero? ? ".home-trending .book-card" : ".home-trending-hero .book-card"
      assert_selector selector

      # Start from the document, then use actual browser key presses through the
      # navigation and hero links rather than focusing the book programmatically.
      page.execute_script("document.activeElement.blur()")
      30.times do
        page.driver.browser.action.send_keys(:tab).perform
        break if page.evaluate_script("document.activeElement.matches(#{selector.to_json})")
      end
      assert page.evaluate_script("document.activeElement.matches(#{selector.to_json})"),
        "A Trending book link must be reachable with Tab"
      expected_path = URI.parse(page.evaluate_script("document.activeElement.href")).path

      page.driver.browser.action.send_keys(:enter).perform

      assert_current_path expected_path
    end
  end

  test "returning from a book after the running switch is disabled shows the current default layout" do
    Flipper.enable_percentage_of_actors(:discovery_hero_trending_v1, 100)
    visit root_path
    assert_selector ".home-trending-hero", count: 1
    within ".home-trending-hero" do
      click_link @books.first.title
    end
    assert_current_path book_path(@books.first)

    Flipper.disable(:discovery_experiment_running_v1)
    page.go_back

    assert_selector "h1", text: "Summer Reading Challenge — Join Now"
    assert_no_selector ".home-trending-hero"
    assert_selector ".home-trending .trending-total", count: 8
  end
end
