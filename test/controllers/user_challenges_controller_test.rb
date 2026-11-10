require "test_helper"

class UserChallengesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "leaving a challenge marks it abandoned and redirects to the challenge" do
    enrollment = create_active_enrollment
    sign_in enrollment.user

    delete user_challenge_path(enrollment)

    assert_redirected_to challenge_path(enrollment.challenge)
    assert_equal "You've left this challenge.", flash[:notice]
    assert enrollment.reload.abandoned?
  end

  test "a conflicting progress update redirects back with a retry alert without abandoning the challenge" do
    enrollment = create_active_enrollment
    sign_in enrollment.user
    update_progress_before_abandoning

    delete user_challenge_path(enrollment), headers: { "HTTP_REFERER" => challenge_url(enrollment.challenge) }

    assert_redirected_to challenge_path(enrollment.challenge)
    assert_equal "Your challenge was updated by another process. Please try again.", flash[:alert]
    assert_nil flash[:notice]
    assert enrollment.reload.active?
    assert_equal 7, enrollment.progress
  end

  test "a conflicting progress update redirects to the challenge index when no referrer is present" do
    enrollment = create_active_enrollment
    sign_in enrollment.user
    update_progress_before_abandoning

    delete user_challenge_path(enrollment)

    assert_redirected_to challenges_path
    assert_equal "Your challenge was updated by another process. Please try again.", flash[:alert]
    assert enrollment.reload.active?
  end

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

  private

  def create_active_enrollment
    challenge = Challenge.create!(
      title: "Weekend Pages",
      goal_type: :pages_per_day,
      goal_value: 20,
      starts_at: 1.day.ago,
      ends_at: 7.days.from_now,
      active: true
    )
    UserChallenge.create!(user: users(:leika), challenge: challenge, status: :active, progress: 0)
  end

  def update_progress_before_abandoning
    allow_any_instance_of(UserChallenge).to receive(:update).and_wrap_original do |original, *arguments|
      UserChallenge.find(original.receiver.id).update!(progress: 7)
      original.call(*arguments)
    end
  end
end
