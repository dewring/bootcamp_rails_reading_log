require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guests see catalog and sign in before sign up without personal controls" do
    get root_path

    assert_response :success
    assert_navigation_links("nav_menu_dropdown", [ "Catalog" ], 0)
    assert_navigation_links("account_dropdown", [ "Sign In", "Sign Up" ], 0)
    assert_select ".nav-actions > li", count: 2
    assert_select "#notifications_panel", count: 0
  end

  test "members see page navigation in Menu and account actions in Account" do
    sign_in users(:leika)
    get root_path

    assert_response :success
    assert_signed_in_navigation("nav_menu_dropdown", "account_dropdown", admin: false)
  end

  test "admins see the same navigation groups on public and workspace pages" do
    sign_in users(:admin)

    [
      [ root_path, "nav_menu_dropdown", "account_dropdown" ],
      [ admin_root_path, "admin_workspace_nav_menu", "admin_workspace_account_menu" ]
    ].each do |path, menu_id, account_id|
      get path

      assert_response :success
      assert_signed_in_navigation(menu_id, account_id, admin: true)
    end
  end

  private

  def assert_signed_in_navigation(menu_id, account_id, admin:)
    labels = [ "Catalog", "Challenges", "Book Clubs", "My Log", "Reviews", "History" ]
    labels.push("Manage") if admin
    assert_navigation_links(menu_id, labels, admin ? 2 : 1)
    assert_navigation_links(account_id, [ "Settings", "Log Out" ], 1)
    assert_select ".nav-actions > li" do |controls|
      assert_equal [ "nav-menu", "notification-menu", "account-menu" ], controls.map { |control| control["class"] }
    end
    assert_select "##{account_id} a[href='#{destroy_user_session_path}'][data-turbo-method='delete']", count: 1
    assert_select "##{menu_id} > li:nth-child(4)[aria-hidden='true'] img[src*='dropdown-divider']", count: 1
    assert_select "##{menu_id} > li:nth-child(8)[aria-hidden='true']", count: admin ? 1 : 0
  end

  def assert_navigation_links(id, labels, dividers)
    assert_select "##{id}[hidden]", count: 1
    assert_select "##{id} > li > a" do |links|
      assert_equal labels, links.map { |link| link.text.strip }
    end
    assert_select "##{id} > li[aria-hidden='true']", count: dividers
    assert_select "button[aria-controls='#{id}'][aria-expanded='false']", count: 1
  end
end
