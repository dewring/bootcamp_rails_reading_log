require "test_helper"

class UserChallengesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "leaving a challenge after the progress job updates it redirects back with a retry alert" do
    travel_to Time.zone.local(2026, 11, 9, 12) do
      user = users(:leika)
      challenge = Challenge.create!(
        title: "Daily Pages",
        goal_type: :pages_per_day,
        goal_value: 20,
        starts_at: 1.day.ago,
        ends_at: 7.days.from_now,
        active: true
      )
      enrollment = UserChallenge.create!(user: user, challenge: challenge, status: :in_progress, progress: 50)
      sign_in user
      original_policy_constructor = UserChallengePolicy.method(:new)
      policy_after_progress_update = lambda do |policy_user, record|
        # The controller has loaded its copy; let the real job save a newer version before authorization returns.
        ChallengeProgressJob.new.perform(user)
        original_policy_constructor.call(policy_user, record)
      end

      UserChallengePolicy.stub(:new, policy_after_progress_update) do
        delete user_challenge_path(enrollment), headers: { "HTTP_REFERER" => challenge_url(challenge) }
      end

      assert enrollment.reload.failed?
      assert_equal 0, enrollment.progress
      assert_equal 1, enrollment.lock_version
      assert_redirected_to challenge_path(challenge)
      assert_equal "Your challenge was updated by another process. Please try again.", flash[:alert]
      assert_nil flash[:notice]
    end
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
end
