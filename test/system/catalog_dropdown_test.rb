require "application_system_test_case"

class CatalogDropdownTest < ApplicationSystemTestCase
  test "hover and keyboard focus differ from selection while disabled options stay neutral" do
    visit books_path(filter: "new_books")
    # Verify menu states without Turbo prefetch issuing a separate catalog request.
    page.execute_script('document.getElementById("catalog-filter-menu").dataset.turboPrefetch = "false"')
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
end
