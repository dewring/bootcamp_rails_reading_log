require "test_helper"

class DropdownActionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "public navigation and catalog dropdowns declare outside-click and Escape actions" do
    [ root_path, books_path ].each do |path|
      get path

      assert_response :success
      assert_dropdown_global_actions(%w[nav-menu account-dropdown])
    end
  end

  test "signed-in public and admin dropdowns include notification global actions" do
    sign_in users(:admin)

    [ root_path, books_path, admin_root_path, admin_catalog_path, admin_reviews_path, admin_book_clubs_path, admin_members_path ].each do |path|
      get path

      assert_response :success
      assert_dropdown_global_actions(%w[nav-menu account-dropdown notification-dropdown])
    end
  end

  test "admin select options provide Stimulus action parameters for submitted values" do
    sign_in users(:admin)

    get admin_root_path, params: { new_challenge: "1" }
    assert_response :success
    %w[books_total pages_per_day true false].each do |value|
      assert_select "button[data-action='click->select-dropdown#select'][data-select-dropdown-value-param='#{value}']", count: 1
    end
    assert_select "[data-select-dropdown-target='option'][data-value]", count: 0

    get admin_members_path, params: { member_id: users(:leika).id }
    assert_response :success
    %w[active suspended].each do |value|
      assert_select "button[data-action='click->select-dropdown#select'][data-select-dropdown-value-param='#{value}']", count: 1
    end
    assert_select "[data-select-dropdown-target='option'][data-value]", count: 0
  end

  private

  def assert_dropdown_global_actions(identifiers)
    identifiers.each do |identifier|
      assert_select "[data-controller~='#{identifier}']" do |dropdowns|
        dropdowns.each do |dropdown|
          actions = dropdown["data-action"].to_s.split
          assert_includes actions, "click@document->#{identifier}#closeOnOutsideClick", request.path
          assert_includes actions, "keydown.esc@document->#{identifier}#closeOnEscape", request.path
        end
      end
    end
  end
end
