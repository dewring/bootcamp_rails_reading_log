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
    assert_select ".admin-table-empty", text: "No challenges created yet."
    assert_select ".admin-pagination", text: /Showing\s+0\s+of\s+0/
    assert_select ".admin-pagination a, .admin-pagination button", count: 0
  end

  test "admin paginates challenges while preserving totals and selected detail" do
    challenges = 6.times.map do |index|
      Challenge.create!(title: "Paginated Challenge #{index}", goal_type: :books_total, goal_value: 6,
        starts_at: (index + 1).days.ago, ends_at: 30.days.from_now)
    end
    selected = challenges.last
    sign_in users(:admin)

    get admin_root_path, params: { challenge_id: selected.id }

    assert_response :success
    assert_equal challenges.first(4).map(&:id), assigns(:challenges).map(&:id)
    assert_select ".admin-challenge-table tbody tr", count: 4
    assert_select ".admin-record-toolbar p", text: /6 records/
    assert_select ".admin-pagination", text: /Showing\s+4\s+of\s+6/
    assert_select ".admin-pagination a[href*='page=2'][href*='challenge_id=#{selected.id}']"
    assert_select "form.admin-detail-form[action='#{admin_challenge_path(selected)}']"

    get admin_root_path, params: { page: 2, challenge_id: selected.id }

    assert_response :success
    assert_equal challenges.last(2).map(&:id), assigns(:challenges).map(&:id)
    assert_select ".admin-challenge-table tbody tr", count: 2
    assert_select ".admin-pagination", text: /Showing\s+2\s+of\s+6/
    assert_select ".admin-pagination [aria-current='page']", text: "2"
    assert_select "a.admin-challenge-name[href*='page=2'][href*='challenge_id=#{selected.id}']"
    assert_select "form.admin-detail-form[action='#{admin_challenge_path(selected)}']"
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
end
