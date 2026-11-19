require "application_system_test_case"

class CatalogGridTest < ApplicationSystemTestCase
  test "a single catalog book starts in the first column at full-row card width" do
    Book.where.not(id: books(:refactoring).id).destroy_all

    visit books_path

    geometry = catalog_geometry
    assert_equal 1, geometry.fetch("items").size
    assert_in_delta geometry.fetch("listLeft"), geometry.fetch("items").first.fetch("left"), 1
    assert_in_delta full_row_column_width(geometry), geometry.fetch("items").first.fetch("width"), 1
  end

  test "four catalog books keep full-row column widths and leave the fifth column empty" do
    Book.destroy_all
    4.times { |index| Book.create!(title: "Grid Book #{index}", author: "Grid Author") }

    visit books_path

    geometry = catalog_geometry
    items = geometry.fetch("items")
    assert_equal 4, items.size
    assert_in_delta geometry.fetch("listLeft"), items.first.fetch("left"), 1
    items.each { |item| assert_in_delta full_row_column_width(geometry), item.fetch("width"), 1 }
    assert_equal 1, items.map { |item| item.fetch("top").round }.uniq.size
  end

  test "a full desktop row holds at most five books" do
    Book.destroy_all
    6.times { |index| Book.create!(title: "Row Book #{index}", author: "Row Author") }

    visit books_path

    tops = catalog_geometry.fetch("items").map { |item| item.fetch("top").round }
    assert_equal 5, tops.count(tops.first)
    assert_operator tops.last, :>, tops.first
  end

  # System tests block the Pico CDN, so page-level widths differ from production;
  # these checks measure the catalog against itself instead of the window.
  test "on a phone-width screen the sidebar stacks above two-column results" do
    Book.destroy_all
    4.times { |index| Book.create!(title: "Mobile Book #{index}", author: "Mobile Author") }
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 900, deviceScaleFactor: 1, mobile: false)

    visit books_path

    layout = page.evaluate_script(<<~JS)
      (() => {
        const catalog = document.querySelector(".catalog-page").getBoundingClientRect()
        const sidebar = document.querySelector(".catalog-sidebar").getBoundingClientRect()
        const content = document.querySelector(".catalog-content").getBoundingClientRect()
        const items = Array.from(document.querySelectorAll(".catalog-page .book-list > .book-list-item")).map(item => item.getBoundingClientRect())
        const checkbox = document.querySelector(".catalog-genre-option .catalog-checkbox")
        return {
          catalogLeft: catalog.left,
          catalogRight: catalog.right,
          sidebarWidth: sidebar.width,
          catalogWidth: catalog.width,
          sidebarBottom: sidebar.bottom,
          contentTop: content.top,
          itemLefts: items.map(box => box.left),
          itemRights: items.map(box => box.right),
          firstRowCount: items.filter(box => Math.round(box.top) === Math.round(items[0].top)).length,
          checkboxShown: getComputedStyle(checkbox).display !== "none"
        }
      })()
    JS

    assert_in_delta layout.fetch("catalogWidth"), layout.fetch("sidebarWidth"), 1
    assert_operator layout.fetch("sidebarBottom"), :<=, layout.fetch("contentTop") + 1
    layout.fetch("itemLefts").each { |left| assert_operator left, :>=, layout.fetch("catalogLeft") }
    layout.fetch("itemRights").each { |right| assert_operator right, :<=, layout.fetch("catalogRight") }
    assert_equal 2, layout.fetch("firstRowCount")
    assert_not layout.fetch("checkboxShown"), "Genres should show as chips without checkboxes on phones"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def catalog_geometry
    assert_selector ".catalog-page .book-list .book-list-item", minimum: 1
    page.evaluate_script(<<~JS)
      (() => {
        const list = document.querySelector(".catalog-page .book-list")
        const listBox = list.getBoundingClientRect()
        const gap = parseFloat(getComputedStyle(list).columnGap)
        const items = Array.from(list.querySelectorAll(":scope > .book-list-item")).map(item => {
          const box = item.getBoundingClientRect()
          return { left: box.left, top: box.top, width: box.width }
        })
        return { listLeft: listBox.left, listWidth: listBox.width, gap: gap, items: items }
      })()
    JS
  end

  def full_row_column_width(geometry)
    (geometry.fetch("listWidth") - 4 * geometry.fetch("gap")) / 5
  end
end
