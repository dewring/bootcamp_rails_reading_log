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
    assert_select "button[aria-controls='admin-report-period-menu'][aria-expanded='false']", text: /Last 7 days/
    assert_select "#admin-report-period-menu[hidden] a[aria-current='true']", text: /Last 7 days\s+7 dates/
    assert_select "#admin-report-period-menu hr", count: 1
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

  test "guests and regular readers are turned away before any reading_sessions query runs" do
    report_queries = []
    record_query = lambda do |_name, _start, _finish, _id, payload|
      report_queries.push(payload[:sql]) if payload[:sql].include?("reading_sessions")
    end

    ActiveSupport::Notifications.subscribed(record_query, "sql.active_record") do
      get admin_report_path
      sign_in users(:leika)
      get admin_report_path
    end

    assert_empty report_queries
  end

  test "admins see overview totals for the selected period" do
    sign_in users(:admin)
    ReadingSession.create!(user: users(:leika), book: books(:refactoring), read_on: Date.new(2026, 11, 5), pages_read: 1200)
    ReadingSession.create!(user: users(:jaina), book: books(:pragmatic), read_on: Date.new(2026, 11, 6), pages_read: 30)

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path, params: { period: "custom", start: "2026-11-05", end: "2026-11-06" }
    end

    assert_response :success
    assert_select ".admin-report-stat", text: /Active readers\s+2 readers/
    assert_select ".admin-report-stat", text: /Reading sessions\s+2 sessions/
    assert_select ".admin-report-stat", text: /Pages read\s+1,230 pages/
    assert_select ".admin-report-stat", text: /Books read\s+2 books/
  end

  test "admins see the chosen sorting column and sorting links preserve the custom period" do
    sign_in users(:admin)
    ReadingSession.create!(user: users(:leika), book: books(:refactoring), read_on: Date.new(2026, 11, 5), pages_read: 90)
    ReadingSession.create!(user: users(:jaina), book: books(:pragmatic), read_on: Date.new(2026, 11, 5), pages_read: 10)
    ReadingSession.create!(user: users(:leika), book: books(:pragmatic), read_on: Date.new(2026, 11, 6), pages_read: 10)

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path, params: { period: "custom", start: "2026-11-05", end: "2026-11-06", sort: "sessions" }
    end

    assert_response :success
    assert_select ".admin-report-table th[aria-sort='descending']", text: "Sessions"
    assert_select ".admin-report-table tbody tr:first-child th[scope='row']", text: /#{books(:pragmatic).title}/
    assert_select ".admin-report-table tbody tr:first-child td:last-child", text: "18.2%"
    assert_select "button[aria-controls='admin-report-sort-menu'][aria-expanded='false']", text: /Sessions/
    assert_select "nav#admin-report-sort-menu[hidden]" do
      assert_select "a[aria-current='true']", text: /Sessions/
      assert_select "a", count: 3 do |links|
        links.each do |link|
          query = Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)
          assert_equal "custom", query["period"]
          assert_equal "2026-11-05", query["start"]
          assert_equal "2026-11-06", query["end"]
          assert_equal "most_read", query["tab"]
          assert_includes [ "pages_read", "sessions", "readers" ], query["sort"]
        end
      end
    end
  end

  test "the custom range Cancel link drops the custom dates and keeps the leaderboard tab and sort" do
    sign_in users(:admin)

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path, params: { period: "custom", start: "2026-11-05", end: "2026-11-06", tab: "power_users", sort: "pages_read" }
    end

    assert_response :success
    assert_select "form.admin-report-period-form a.admin-report-cancel", text: "Cancel" do |links|
      uri = URI.parse(links.first["href"])
      query = Rack::Utils.parse_nested_query(uri.query)

      assert_equal admin_report_path, uri.path
      assert_equal({ "tab" => "power_users", "sort" => "pages_read" }, query)
    end
  end

  test "the power users tab shows readers by nickname and keeps the tab when sorting" do
    sign_in users(:admin)
    ReadingSession.create!(user: users(:leika), book: books(:refactoring), read_on: Date.new(2026, 11, 5), pages_read: 20)

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path, params: { period: "last_7_days", tab: "power_users" }
    end

    assert_response :success
    assert_select ".admin-report-tabs a[aria-current='page']", text: /Power users/
    assert_select ".admin-report-table th[scope='row']", text: /#{users(:leika).nickname}/
    assert_select ".admin-report-table th[aria-sort='descending']", text: "Active days"
    assert_select "#admin-report-period-menu a", count: 4 do |links|
      links.each do |link|
        query = Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)
        assert_equal "power_users", query["tab"]
        assert_equal "active_days", query["sort"]
      end
    end
    assert_select "#admin-report-sort-menu a", count: 4 do |links|
      links.each do |link|
        query = Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)
        assert_equal "power_users", query["tab"]
        assert_equal "last_7_days", query["period"]
      end
    end
  end

  test "an unknown tab shows the most read leaderboard" do
    sign_in users(:admin)

    get admin_report_path, params: { tab: "../../secrets" }

    assert_response :success
    assert_select ".admin-report-tabs a[aria-current='page']", text: /Most read/
  end

  test "the most reactions tab ranks books by reactions changed in the period" do
    sign_in users(:admin)
    reaction = Reaction.create!(user: users(:leika), book: books(:refactoring), kind: "like")
    reaction.update_column(:updated_at, Time.zone.local(2026, 11, 10, 9))

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path, params: { period: "last_7_days", tab: "most_reactions" }
    end

    assert_response :success
    assert_select ".admin-report-tabs a[aria-current='page']", text: /Most reactions\s+1/
    assert_select ".admin-report-table th[scope='row']", text: /#{books(:refactoring).title}/
    assert_select ".admin-report-table th[aria-sort='descending']", text: "Total"
  end

  test "admins see import completeness and ReadingMetric freshness in the report health panel" do
    sign_in users(:admin)
    ReadingMetric.create!(user: users(:leika), calculated_at: Time.zone.local(2026, 11, 11, 17, 52))

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      get admin_report_path
    end

    assert_response :success
    assert_select "aside.admin-report-health h3", text: "Import completeness"
    assert_select "aside.admin-report-health dd", text: %r{/ 100}
    assert_select ".admin-report-health-status"
    assert_select "aside.admin-report-health time[data-controller='local-time'][datetime='2026-11-11T17:52:00Z']"
    assert_select "aside.admin-report-health dd", text: /8 min before as_of/
  end
  test "all leaderboard tabs paginate full results and preserve report filters" do
    sign_in users(:admin)
    report_books = []
    report_users = []
    12.times do |index|
      book = Book.create!(title: "Report book #{format('%02d', index)}", author: "Report author")
      reader = User.create!(first_name: "Report", last_name: "Reader", nickname: "report#{format('%02d', index)}",
        email: "report#{index}@example.com", password: "password123")
      ReadingSession.create!(user: reader, book: book, read_on: Date.new(2026, 11, 5), pages_read: 100 - index)
      reaction = Reaction.create!(user: reader, book: book, kind: "like")
      reaction.update_column(:updated_at, Time.zone.local(2026, 11, 5, 9))
      report_books.push(book)
      report_users.push(reader)
    end

    travel_to Time.zone.local(2026, 11, 11, 18, 0) do
      [ "most_read", "most_reactions", "power_users" ].each do |tab|
        sort = tab == "most_reactions" ? "total" : "pages_read"
        filters = { period: "custom", start: "2026-11-05", end: "2026-11-06", tab: tab, sort: sort }
        get admin_report_path, params: filters

        assert_response :success
        assert_select ".admin-report-table tbody tr", count: 10
        assert_select ".admin-report-leaderboards > footer", count: 0
        next_link = css_select(".admin-report-leaderboards .pagy a[href]").find do |link|
          Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)["page"] == "2"
        end
        assert next_link
        query = Rack::Utils.parse_nested_query(URI.parse(next_link["href"]).query)
        filters.each { |key, value| assert_equal value, query[key.to_s] }
        get next_link["href"]

        assert_response :success
        assert_select ".admin-report-table tbody tr", count: 2
        assert_select ".admin-report-leaderboards > footer", count: 0
        expected_rank = tab == "most_reactions" ? "1" : "11"
        assert_select ".admin-report-table tbody tr:first-child td:first-child", text: expected_rank
        expected_name = tab == "power_users" ? report_users[10].nickname : report_books[10].title
        assert_select ".admin-report-table tbody tr:first-child th[scope='row']", text: /#{expected_name}/

        [ "#admin-report-sort-menu a", "#admin-report-period-menu a", ".admin-report-tabs a" ].each do |selector|
          css_select(selector).each do |link|
            control_query = Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)
            assert_nil control_query["page"]
          end
        end
      end
    end
  end
end
