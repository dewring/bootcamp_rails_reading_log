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
end
