require "application_system_test_case"

class NavigationSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:admin), scope: :user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "public and admin controls align and menus stay vertical on desktop" do
    assert_shared_navigation(1400)
  end

  test "public and admin controls remain visible and aligned on mobile" do
    assert_shared_navigation(390)
  end

  test "guests can open catalog and account menus on desktop and mobile" do
    logout(:user)
    assert_role_navigation([ "Catalog" ], [ "Sign In", "Sign Up" ], notifications: false)
  end

  test "members can open personal links without admin management on desktop and mobile" do
    logout(:user)
    login_as users(:leika), scope: :user
    assert_role_navigation([ "Catalog", "Challenges", "Book Clubs", "My Log", "Reviews", "History" ], [ "Settings", "Log Out" ], notifications: true)
  end

  private

  def assert_role_navigation(menu_labels, account_labels, notifications:)
    [ 1400, 390 ].each do |width|
      prepare_navigation_page(books_path, width)
      assert_selector "button[aria-label='Notifications']", count: notifications ? 1 : 0
      find("button[aria-label='Menu']").hover
      assert_selector ".nav-dropdown", visible: true
      assert_vertical_menu(".nav-dropdown", menu_labels)
      find("button[aria-label='Account']").hover
      assert_selector ".account-dropdown", visible: true
      assert_vertical_menu(".account-dropdown", account_labels)
    end
  end

  def prepare_navigation_page(path, width)
    page.current_window.resize_to(width, 1000)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 1000, deviceScaleFactor: 1, mobile: false)
    visit path
    page.execute_script(<<~JS, Rails.root.join("test/fixtures/stylesheets/pico_navigation.css").read)
      const style = document.createElement("style")
      style.nonce = document.querySelector('meta[name="csp-nonce"]').content
      style.textContent = arguments[0]
      document.head.insertBefore(style, document.querySelector('link[data-turbo-track="reload"]'))
    JS
    assert_equal width, page.evaluate_script("window.innerWidth")
  end

  def assert_shared_navigation(width)
    geometries = [ books_path, admin_root_path ].map do |path|
      prepare_navigation_page(path, width)
      [ "Menu", "Notifications", "Account" ].each do |label|
        assert_selector "button[aria-label='#{label}']", visible: true
      end
      controls = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('.nav-actions > li > button, .nav-actions .notification-trigger')).map(button => {
          const rect = button.getBoundingClientRect()
          return { label: button.getAttribute('aria-label'), x: rect.x, y: rect.y, width: rect.width, height: rect.height }
        })
      JS
      assert_equal [ "Menu", "Notifications", "Account" ], controls.map { |control| control.fetch("label") }
      controls.each do |control|
        assert_equal 44, control.fetch("width")
        assert_equal 44, control.fetch("height")
      end
      find("button[aria-label='Menu']").hover
      assert_selector ".nav-dropdown", visible: true
      assert_vertical_menu(".nav-dropdown", [ "Catalog", "Challenges", "Book Clubs", "My Log", "Reviews", "History", "Manage" ])
      find("button[aria-label='Account']").hover
      assert_selector ".account-dropdown", visible: true
      assert_no_selector ".nav-dropdown", visible: true
      assert_vertical_menu(".account-dropdown", [ "Settings", "Log Out" ])
      find("button[aria-label='Account']").send_keys(:escape)
      assert_no_selector ".account-dropdown", visible: true
      controls
    end
    geometries.first.zip(geometries.last).each do |public_control, admin_control|
      [ "x", "y", "width", "height" ].each do |dimension|
        assert_in_delta public_control.fetch(dimension), admin_control.fetch(dimension), 0.5,
          "#{public_control.fetch('label')} #{dimension} differs between public and admin pages"
      end
    end
  end

  def assert_vertical_menu(selector, labels)
    links = all("#{selector} > li > a")
    assert_equal labels, links.map(&:text)
    bounds = links.map { |link| link.evaluate_script("({x: this.getBoundingClientRect().x, y: this.getBoundingClientRect().y, right: this.getBoundingClientRect().right})") }
    bounds.each do |rect|
      assert_in_delta bounds.first.fetch("x"), rect.fetch("x"), 0.5
      assert_operator rect.fetch("x"), :>=, 0
      assert_operator rect.fetch("right"), :<=, page.evaluate_script("window.innerWidth")
    end
    bounds.each_cons(2) do |previous, current|
      assert_operator current.fetch("y"), :>, previous.fetch("y")
    end
    all("#{selector} > li[aria-hidden='true'] img").each do |divider|
      assert_in_delta links.first.evaluate_script("this.getBoundingClientRect().width"), divider.evaluate_script("this.getBoundingClientRect().width"), 1
    end
  end
end
