require "application_system_test_case"

class NotificationLayoutTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:admin), scope: :user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "notification refresh preserves public navigation positions on desktop" do
    assert_notification_refresh_positions(books_path, ".nav-actions", 1400)
  end

  test "notification refresh preserves public navigation positions on mobile" do
    assert_notification_refresh_positions(books_path, ".nav-actions", 390)
  end

  test "notification refresh preserves admin navigation positions on desktop" do
    assert_notification_refresh_positions(admin_root_path, ".admin-topbar-actions", 1400)
  end

  test "notification refresh preserves admin navigation positions on mobile" do
    assert_notification_refresh_positions(admin_root_path, ".admin-topbar-actions", 390)
  end

  private

  def assert_notification_refresh_positions(path, controls_selector, width)
    page.current_window.resize_to(width, 1000)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 1000, deviceScaleFactor: 1, mobile: false)
    visit path
    styles = [ "pico_navigation.css", "pico_loading.css" ].map do |name|
      Rails.root.join("test/fixtures/stylesheets", name).read
    end.join("\n")
    page.execute_script(<<~JS, styles)
      const style = document.createElement("style")
      style.id = "local-pico-rules"
      style.nonce = document.querySelector('meta[name="csp-nonce"]').content
      style.textContent = arguments[0]
      document.head.insertBefore(style, document.querySelector('link[data-turbo-track="reload"]'))
    JS
    assert page.evaluate_script("document.getElementById('local-pico-rules').sheet !== null"), "Local Pico rules must load under CSP"
    assert_equal width, page.evaluate_script("window.innerWidth")
    find("button[aria-label='Notifications']").hover
    assert_selector "#notifications_dropdown", visible: true
    page.execute_script(<<~JS, controls_selector)
      const controls = document.querySelector(arguments[0])
      const measureControls = () => Array.from(controls.querySelectorAll(
        'button[aria-label="Menu"], button[aria-label="Notifications"], button[aria-label="Account"]'
      )).map(button => {
        const bounds = button.getBoundingClientRect()
        return { label: button.getAttribute("aria-label"), x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height }
      })
      window.notificationLayoutBaseline = measureControls()
      window.notificationLayoutSamples = []
      window.notificationLayoutObserver = new MutationObserver(() => {
        const frame = document.getElementById("notifications_frame")
        if (frame.getAttribute("aria-busy") === "true") {
          window.notificationLayoutSamples.push(measureControls())
        }
      })
      window.notificationLayoutObserver.observe(document.body, {
        attributes: true, childList: true, subtree: true, attributeFilter: ["aria-busy", "busy"]
      })
    JS

    find("a[aria-label='Refresh notifications']").click

    assert_selector "#notifications_frame[complete]:not([busy])"
    assert_selector "#notifications_dropdown", visible: true
    assert_selector "button[aria-label='Notifications'][aria-expanded='true']"
    assert_current_path path
    geometry = page.evaluate_script(<<~JS)
      (() => {
        window.notificationLayoutObserver.disconnect()
        return { before: window.notificationLayoutBaseline, during: window.notificationLayoutSamples }
      })()
    JS
    assert_equal [ "Menu", "Notifications", "Account" ], geometry.fetch("before").map { |button| button.fetch("label") }
    assert_not_empty geometry.fetch("during"), "The test must observe a real Turbo busy state"
    geometry.fetch("during").each do |buttons|
      buttons.zip(geometry.fetch("before")).each do |actual, expected|
        assert_equal expected.fetch("label"), actual.fetch("label")
        [ "x", "y", "width", "height" ].each do |dimension|
          assert_in_delta expected.fetch(dimension), actual.fetch(dimension), 0.5,
            "#{actual.fetch('label')} #{dimension} changed during notification refresh"
        end
      end
    end
  end
end
