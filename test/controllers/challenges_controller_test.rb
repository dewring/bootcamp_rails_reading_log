require "test_helper"

class ChallengesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "index groups challenge cards by reader state" do
    sign_in users(:leika)

    ongoing = Challenge.create!(
      title: "Autumn Reading Sprint",
      goal_type: :books_total,
      goal_value: 6,
      starts_at: 1.day.ago,
      ends_at: 30.days.from_now,
      active: true
    )
    completed = Challenge.create!(
      title: "Finished Classics",
      goal_type: :books_total,
      goal_value: 3,
      starts_at: 30.days.ago,
      ends_at: 1.day.ago,
      active: true
    )
    available = Challenge.create!(
      title: "Weekend Pages",
      goal_type: :pages_per_day,
      goal_value: 20,
      starts_at: 1.day.ago,
      ends_at: 7.days.from_now,
      active: true
    )
    users(:leika).user_challenges.create!(challenge: ongoing, status: :in_progress, progress: 65)
    users(:leika).user_challenges.create!(challenge: completed, status: :completed, progress: 100)

    get challenges_path

    assert_response :success
    assert_select "main.challenges-page"
    assert_select ".challenge-summary-tile--ongoing strong", text: "1"
    assert_select ".challenge-summary-tile--completed strong", text: "1"
    assert_select ".challenge-summary-tile--available strong", text: "1"
    assert_select ".challenge-section--ongoing .challenge-card--ongoing", count: 1
    assert_select ".challenge-section--completed .challenge-card--completed", count: 1
    assert_select ".challenge-section--available .challenge-card--available", count: 1
    assert_select ".challenge-section--completed > .challenge-section-heading p", text: "Previous attempts"
    assert_select ".challenge-card--ongoing [role='progressbar'][aria-valuenow='65']", count: 1
    assert_select ".challenge-card--available .challenge-card-action", text: /Enroll/
  end

  test "index keeps the shared challenge navigation and hero illustration" do
    sign_in users(:leika)

    get challenges_path

    assert_response :success
    assert_select "nav.nav-bar"
    assert_select "section.challenges-hero h1#challenges-title", text: "Read. Track. Celebrate."
    assert_select "img[src*='challenges-reading-character']", count: 1
    assert_select ".challenges-tracking-note", text: /Progress updates automatically from My Log/
  end
end
