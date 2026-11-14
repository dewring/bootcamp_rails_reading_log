require "test_helper"

class CatalogDropdownSelectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
  end

  test "admin filter menus mark only the selected link as current" do
    pages = [
      [ admin_catalog_path(genre: "Fiction"), [ "admin-catalog-genre-menu" ] ],
      [ admin_book_clubs_path(sort: "name"), [ "admin-clubs-sort-menu" ] ],
      [ admin_members_path(status: "active", sort: "name"), [ "admin-member-status-menu", "admin-member-sort-menu" ] ],
      [ admin_reviews_path(rating: "1"), [ "admin-reviews-rating-menu" ] ],
      [ admin_report_path(period: "last_7_days", sort: "sessions"), [ "admin-report-period-menu", "admin-report-sort-menu" ] ]
    ]

    pages.each do |path, menu_ids|
      get path
      assert_response :success
      menu_ids.each do |menu_id|
        assert_select "##{menu_id}" do
          assert_select ".catalog-dropdown-option.is-selected[aria-current='true']", count: 1
          assert_select ".catalog-dropdown-option.is-selected:not([aria-current='true'])", count: 0
          assert_select ".catalog-dropdown-option:not(.is-selected)[aria-current]", count: 0
          assert_select ".catalog-dropdown-option:not(.is-selected):not([aria-current])", minimum: 1
        end
      end
    end
  end

  test "public catalog filters mark only the selected link as current" do
    [ "new_books", "most_read" ].each do |filter|
      get books_path(filter: filter)

      assert_response :success
      assert_select "#catalog-filter-menu" do
        assert_select ".catalog-dropdown-option.is-selected[aria-current='page'][href*='filter=#{filter}']", count: 1
        assert_select ".catalog-dropdown-option.is-selected:not([aria-current='page'])", count: 0
        assert_select ".catalog-dropdown-option:not(.is-selected)[aria-current]", count: 0
        assert_select ".catalog-dropdown-option:not(.is-selected):not([aria-current])", minimum: 1
      end
    end
  end

  test "admin form listboxes mark only their selected option with aria selected" do
    challenge = Challenge.create!(title: "Dropdown selection", goal_type: :books_total, goal_value: 6,
      starts_at: 1.day.ago, ends_at: 30.days.from_now, active: true)

    [ admin_root_path(challenge_id: challenge.id), admin_members_path(member_id: users(:leika).id) ].each do |path|
      get path
      assert_response :success
      assert_select "[role='listbox']", minimum: 1 do |listboxes|
        listboxes.each do |listbox|
          assert_select listbox, ".catalog-dropdown-option.is-selected[role='option'][aria-selected='true']", count: 1
          assert_select listbox, ".catalog-dropdown-option.is-selected:not([aria-selected='true'])", count: 0
          assert_select listbox, ".catalog-dropdown-option:not(.is-selected)[aria-selected='true']", count: 0
          assert_select listbox, ".catalog-dropdown-option:not(.is-selected)[role='option'][aria-selected='false']", minimum: 1
        end
      end
    end
  end
end
