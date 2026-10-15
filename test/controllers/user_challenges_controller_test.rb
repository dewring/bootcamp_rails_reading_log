require "test_helper"

class UserChallengesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "enrolling from an available challenge returns to the index and shows it as ongoing" do
    sign_in users(:leika)
    challenge = Challenge.create!(
      title: "Weekend Pages",
      goal_type: :pages_per_day,
      goal_value: 20,
      starts_at: 1.day.ago,
      ends_at: 7.days.from_now,
      active: true
    )

    post user_challenges_path, params: { user_challenge: { challenge_id: challenge.id } }

    assert_redirected_to challenges_path
    assert_equal "active", UserChallenge.find_by(user: users(:leika), challenge: challenge).status

    follow_redirect!

    assert_response :success
    assert_select ".challenge-section--ongoing .challenge-card--ongoing h3", text: challenge.title
    assert_select ".challenge-section--ongoing .challenge-card--ongoing h3 a", count: 0
    assert_select ".challenge-section--available h3", text: challenge.title, count: 0
  end
end
