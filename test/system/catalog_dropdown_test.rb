require "application_system_test_case"

class CatalogDropdownTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown do
    Warden.test_reset!
  end
  test "hover and keyboard focus differ from selection while disabled options stay neutral" do
    visit books_path(filter: "new_books")
    find("button[aria-controls='catalog-filter-menu']").click

    selected = find("#catalog-filter-menu .is-selected[aria-current='page']")
    other = find("#catalog-filter-menu a[href*='filter=most_read']")
    disabled = find("#catalog-filter-menu [aria-disabled='true']")

    selected.hover
    assert_equal "rgba(253, 241, 239, 1)", selected.style("background-color").fetch("background-color")
    assert_equal "700", selected.style("font-weight").fetch("font-weight")

    other.hover
    assert_equal "rgba(243, 243, 243, 1)", other.style("background-color").fetch("background-color")
    assert_equal "rgba(44, 38, 35, 1)", other.style("color").fetch("color")

    disabled.hover
    assert_equal "rgba(255, 255, 255, 1)", disabled.style("background-color").fetch("background-color")

    find("button[aria-controls='catalog-filter-menu']").send_keys(:tab)
    assert_equal selected, find("#catalog-filter-menu a:focus")
    assert selected.matches_css?(":focus-visible")
    assert_equal "rgba(253, 241, 239, 1)", selected.style("background-color").fetch("background-color")
    assert_equal "solid", selected.style("outline-style").fetch("outline-style")

    selected.send_keys(:tab)
    assert other.matches_css?(":focus-visible")
    assert_equal "rgba(243, 243, 243, 1)", other.style("background-color").fetch("background-color")
    assert_equal "solid", other.style("outline-style").fetch("outline-style")
  end

  test "sort menu groups stay compact instead of taking Pico input-group spacing" do
    # The CSP style nonce comes from the session id, so a signed-in session is
    # needed for the injected local Pico rules to load.
    Warden.test_mode!
    login_as users(:leika), scope: :user
    visit books_path
    page.execute_script(<<~JS, Rails.root.join("test/fixtures/stylesheets/pico_group.css").read)
      const style = document.createElement("style")
      style.id = "local-pico-group"
      style.nonce = document.querySelector('meta[name="csp-nonce"]').content
      style.textContent = arguments[0]
      document.head.append(style)
    JS
    assert page.evaluate_script("document.getElementById('local-pico-group').sheet !== null"), "Local Pico group rules must load under CSP"
    find("button[aria-controls='catalog-sort-menu']").click

    groups = all("#catalog-sort-menu .catalog-sort-group", count: 2)
    assert_equal "0px", groups.first.style("margin-bottom").fetch("margin-bottom")
    assert_equal "11px", groups.first.find(".catalog-sort-group-label").style("font-size").fetch("font-size")
    assert_operator page.evaluate_script("document.querySelector('#catalog-sort-menu').getBoundingClientRect().height"), :<, 220
  end
end
