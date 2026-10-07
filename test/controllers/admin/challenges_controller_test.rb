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
    assert_select "img[src*='admin-eye'], img[src*='admin-pencil']", count: 0
  end

  test "admin workspace does not show a detail card before a challenge is selected" do
    sign_in users(:admin)

    get admin_root_path

    assert_response :success
    assert_select "aside.admin-detail-panel", count: 0
    assert_select ".admin-workspace--no-selection", count: 1
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
