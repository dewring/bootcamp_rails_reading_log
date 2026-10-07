require "test_helper"

class AdminSidebarTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "workspace pages retain the same navigation order and highlight their own section" do
    sign_in users(:admin)

    [
      [ admin_root_path, "Challenges" ],
      [ admin_catalog_path, "Catalog" ],
      [ admin_root_path(new_challenge: true), "Challenges" ],
      [ admin_catalog_path(new_book: true), "Catalog" ]
    ].each do |path, active_section|
      get path

      assert_response :success
      assert_select ".admin-sidebar-nav > .admin-sidebar-link" do |items|
        assert_equal [ "Catalog", "Reviews", "Challenges", "Book Clubs", "Members", "Settings" ], items.map { |item| item.text.strip }
      end
      assert_select ".admin-sidebar-nav a[href='#{admin_root_path}']", text: "Challenges"
      assert_select ".admin-sidebar-nav a[href='#{admin_catalog_path}']", text: "Catalog"
      assert_select ".admin-sidebar-nav .is-active[aria-current='page']", count: 1, text: active_section
      assert_select ".admin-sidebar-nav .admin-sidebar-icon[aria-hidden='true']", count: 6
      assert_select ".admin-sidebar-nav img", count: 0
      assert_select ".admin-sidebar-footer a[data-turbo-method='delete']", text: "Log out"
    end
  end
end
