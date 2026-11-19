require "test_helper"

class Admin::ChallengesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest is sent to sign in" do
    get admin_root_path

    assert_redirected_to new_user_session_path
  end

  test "regular user cannot open the admin workspace" do
    sign_in users(:leika)

    get admin_root_path

    assert_redirected_to root_path
  end

  test "admin sees the challenge management workspace" do
    challenge = Challenge.create!(
      title: "Autumn Reading Sprint",
      goal_type: :books_total,
      goal_value: 6,
      starts_at: 1.day.ago,
      ends_at: 30.days.from_now,
      active: true
    )
    sign_in users(:admin)

    get admin_root_path, params: { challenge_id: challenge.id }

    assert_response :success
    assert_select "main.admin-main"
    assert_select "h1#admin-page-title", "Challenge Management"
    assert_select ".admin-challenge-table tbody tr", count: 1
    assert_select ".admin-challenge-name strong", text: challenge.title
    assert_select "form.admin-detail-form[action='#{admin_challenge_path(challenge)}']"
    assert_select "input[name='challenge[title]'][value='#{challenge.title}']"
    assert_select ".admin-row-actions a", count: 0
    assert_select ".admin-row-actions button", count: 1
    assert_select ".admin-row-actions form[action='#{admin_challenge_path(challenge)}']" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button[aria-label='Delete #{challenge.title}']"
    end
    assert_select "img[src*='admin-eye'], img[src*='admin-pencil']", count: 0
    assert_select ".admin-pagination a, .admin-pagination button", count: 0
  end

  test "admin workspace does not show a detail card before a challenge is selected" do
    sign_in users(:admin)

    get admin_root_path

    assert_response :success
    assert_select "aside.admin-detail-panel", count: 0
    assert_select ".admin-workspace--no-selection", count: 1
    assert_select ".admin-table-empty .empty-state--compact .empty-state-title", text: "No challenges created yet"
    assert_select ".admin-pagination", text: /Showing\s+0\s+of\s+0/
    assert_select ".admin-pagination a, .admin-pagination button", count: 0
  end

  test "admin paginates challenges ten per page while preserving totals and selected detail" do
    challenges = 12.times.map do |index|
      Challenge.create!(title: "Paginated Challenge #{index}", goal_type: :books_total, goal_value: 6,
        starts_at: (index + 1).days.ago, ends_at: 30.days.from_now)
    end
    selected = challenges.last
    sign_in users(:admin)

    get admin_root_path, params: { challenge_id: selected.id }

    assert_response :success
    assert_equal challenges.first(10).map(&:id), assigns(:challenges).map(&:id)
    assert_select ".admin-challenge-table tbody tr", count: 10
    assert_select ".admin-record-toolbar p", text: /12 records/
    assert_select ".admin-pagination", text: /Showing\s+10\s+of\s+12/
    assert_select ".admin-pagination a[href*='page=2'][href*='challenge_id=#{selected.id}']"
    assert_select "form.admin-detail-form[action='#{admin_challenge_path(selected)}']"

    get admin_root_path, params: { page: 2, challenge_id: selected.id }

    assert_response :success
    assert_equal challenges.last(2).map(&:id), assigns(:challenges).map(&:id)
    assert_select ".admin-challenge-table tbody tr", count: 2
    assert_select ".admin-pagination", text: /Showing\s+2\s+of\s+12/
    assert_select ".admin-pagination [aria-current='page']", text: "2"
    assert_select "a.admin-challenge-name[href*='page=2'][href*='challenge_id=#{selected.id}']"
    assert_select "form.admin-detail-form[action='#{admin_challenge_path(selected)}']"
  end

  test "status filter returns only challenges whose badge shows that status" do
    now = Time.zone.local(2026, 11, 18, 12)
    ongoing = Challenge.create!(title: "Running Now", goal_type: :books_total, goal_value: 1, starts_at: now - 1.day, ends_at: now + 1.day)
    upcoming = Challenge.create!(title: "Starts Later", goal_type: :books_total, goal_value: 1, starts_at: now + 2.days, ends_at: now + 9.days)
    expired = Challenge.create!(title: "Already Over", goal_type: :books_total, goal_value: 1, starts_at: now - 9.days, ends_at: now - 2.days)
    inactive = Challenge.create!(title: "Switched Off", goal_type: :books_total, goal_value: 1, starts_at: now - 1.day, ends_at: now + 1.day, active: false)
    sign_in users(:admin)

    { "ongoing" => ongoing, "upcoming" => upcoming, "expired" => expired, "inactive" => inactive }.each do |status, challenge|
      travel_to(now) { get admin_root_path, params: { status: status } }

      assert_response :success
      assert_includes assigns(:challenges), challenge
      assert assigns(:challenges).all? { |listed| listed.schedule_status(now) == status }, "#{status} filter listed another status"
      assert_select "button[aria-controls='admin-challenge-status-menu']", text: status.capitalize
      assert_select "#admin-challenge-status-menu a.is-selected[href*='status=#{status}']", count: 1
    end
  end

  test "challenges sort by start date or name in either direction and keep the status filter" do
    sign_in users(:admin)
    Challenge.create!(title: "Aaa First Name", goal_type: :books_total, goal_value: 1, starts_at: 1.day.ago, ends_at: 5.days.from_now)
    Challenge.create!(title: "Zzz Last Name", goal_type: :books_total, goal_value: 1, starts_at: 3.days.ago, ends_at: 5.days.from_now)

    {
      { sort: "starts", direction: "desc" } => [ { starts_at: :desc, id: :desc }, "Start date · Newest first" ],
      { sort: "starts", direction: "asc" } => [ { starts_at: :asc, id: :asc }, "Start date · Oldest first" ],
      { sort: "name", direction: "asc" } => [ { title: :asc, id: :asc }, "Name · A–Z" ],
      { sort: "name", direction: "desc" } => [ { title: :desc, id: :desc }, "Name · Z–A" ]
    }.each do |options, (expected_order, label)|
      get admin_root_path, params: options.merge(status: "ongoing")

      assert_response :success
      expected = Challenge.with_schedule_status("ongoing").reorder(expected_order).limit(10).pluck(:id)
      assert_equal expected, assigns(:challenges).map(&:id), "#{label} returned the wrong order"
      assert_select "button[aria-controls='admin-challenge-sort-menu']", text: label
      assert_select "#admin-challenge-sort-menu a[href*='status=ongoing']", count: 4
    end
  end

  test "invalid challenge creation renders errors with initialized pagination" do
    Challenge.create!(title: "Existing Challenge", goal_type: :books_total, goal_value: 6,
      starts_at: 1.day.ago, ends_at: 30.days.from_now)
    sign_in users(:admin)

    assert_no_difference "Challenge.count" do
      post admin_challenges_path, params: { challenge: {
        title: "", goal_type: "books_total", goal_value: 6, starts_at: 1.day.ago, ends_at: 30.days.from_now
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".admin-validation-errors", text: /Title can't be blank/
    assert_select ".admin-challenge-table tbody tr", count: 1
    assert_select ".admin-pagination", text: /Showing\s+1\s+of\s+1/
    assert_select "form.admin-detail-form[action='#{admin_challenges_path}']"
    assert_select "input[name='challenge[goal_value]'][value='6']"
  end

  test "admin updates a challenge from the inline detail form" do
    challenge = Challenge.create!(
      title: "Pages Every Day",
      goal_type: :pages_per_day,
      goal_value: 20,
      starts_at: 1.day.ago,
      ends_at: 30.days.from_now,
      active: true
    )
    sign_in users(:admin)

    patch admin_challenge_path(challenge), params: { challenge: { title: "Pages Every Morning" } }

    assert_redirected_to admin_root_path(challenge_id: challenge.id)
    assert_equal "Pages Every Morning", challenge.reload.title
  end

  test "a status filter with no matches explains it and offers to clear the filter" do
    sign_in users(:admin)

    get admin_root_path, params: { status: "inactive", sort: "name", direction: "asc" }

    assert_response :success
    assert_select ".admin-table-empty .empty-state-title", text: "No inactive challenges"
    assert_select ".admin-table-empty a.empty-state-action[href='#{admin_root_path(sort: "name", direction: "asc")}']", text: "Clear filter"
  end
end
