require "test_helper"

class Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guests are redirected to sign in instead of seeing the report" do
    get admin_report_path
    assert_redirected_to new_user_session_path
  end

  test "signed-in regular readers are redirected home instead of seeing the report" do
    sign_in users(:leika)
    get admin_report_path
    assert_redirected_to root_path
  end

  test "admins see the report page with Reports listed first and marked active in the sidebar" do
    sign_in users(:admin)
    get admin_report_path

    assert_response :success
    assert_select "h1", text: "Reading Activity Report"
    assert_select ".admin-sidebar-nav a:first-child", text: "Reports"
    assert_select ".admin-sidebar-nav .is-active[aria-current='page']", text: "Reports"
  end

  test "admins see the selected preset range and the as_of time" do
    sign_in users(:admin)

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path, params: { period: "last_7_days" }
    end

    assert_response :success
    assert_select "h2#admin-report-range-title", text: /November 5, 2026 – November 11, 2026/
    assert_select "select[name='period'] option[selected][value='last_7_days']"
    assert_select ".admin-report-as-of time[data-controller='local-time'][datetime='2026-11-11T18:00:00Z']", text: "November 11, 2026 18:00 UTC"
    assert_select ".admin-report-error", count: 0
  end

  test "an invalid custom range shows the error and the default today range" do
    sign_in users(:admin)

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path, params: { period: "custom", start: "2026-11-05", end: "2026-11-01" }
    end

    assert_response :success
    assert_select ".admin-report-error", text: /End date must be on or after the start date\./
    assert_select "h2#admin-report-range-title", text: "November 11, 2026"
    assert_select "input[type='date'][name='start'][value='2026-11-05']"
  end
end
