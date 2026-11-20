require "test_helper"

class DevelopmentReadingScenarioPlanTest < ActiveSupport::TestCase
  setup do
    @as_of = Time.zone.local(2026, 10, 30, 12)
    @plan = DevelopmentReadingScenarioPlan.new(as_of: @as_of).static_records
  end

  test "the challenge plan includes two challenges per goal type with valid dates and goals" do
    challenges = @plan.fetch("challenges")

    assert_equal 6, challenges.length
    assert_equal 6, challenges.map { |entry| entry.fetch("identity") }.uniq.length
    assert_equal 6, challenges.map { |entry| entry.fetch("attributes").fetch("title") }.uniq.length
    assert_equal({ "pages_per_day" => 2, "books_total" => 2, "streak_days" => 2 }, challenges.map { |entry| entry.fetch("attributes").fetch("goal_type") }.tally)
    challenges.each do |entry|
      challenge = Challenge.new(entry.fetch("attributes"))
      assert challenge.valid?, challenge.errors.full_messages.join(", ")
      assert challenge.active?
      assert_operator challenge.starts_at, :<, @as_of
      assert_operator challenge.ends_at, :>, @as_of
    end
  end

  test "ten readers join three challenges ten join one and ten join none in the plan" do
    plan = @plan
    enrollments = plan.fetch("user_challenges")
    by_reader = enrollments.group_by { |entry| entry.fetch("reader") }
    counts = plan.fetch("users").select { |entry| entry.fetch("attributes").fetch("role") == "user" }.map do |reader|
      by_reader.fetch(reader.fetch("identity"), []).length
    end

    assert_equal({ 3 => 10, 1 => 10, 0 => 10 }, counts.tally)
    assert_equal 40, enrollments.length
    assert_equal 40, enrollments.map { |entry| entry.fetch("identity") }.uniq.length
    assert_equal 40, enrollments.map { |entry| entry.values_at("reader", "challenge") }.uniq.length
    assert_equal plan.fetch("challenges").map { |entry| entry.fetch("identity") }.sort, enrollments.map { |entry| entry.fetch("challenge") }.uniq.sort
    assert_not by_reader.key?("admin")
  end

  test "all 30 synthetic readers and the synthetic admin are active and use reserved email addresses" do
    users = @plan.fetch("users")

    assert_equal 30, users.count { |user| user.fetch("attributes").fetch("role") == "user" }
    assert_equal 1, users.count { |user| user.fetch("attributes").fetch("role") == "admin" }
    assert users.all? { |user| user.fetch("attributes").fetch("account_status") == "active" }
    assert users.all? { |user| user.fetch("attributes").fetch("email").end_with?("@example.test") }
    assert_equal 31, users.map { |user| user.fetch("attributes").fetch("email") }.uniq.length
    assert_equal 31, users.map { |user| user.fetch("attributes").fetch("nickname") }.uniq.length
    assert users.none? { |user| user.fetch("attributes").key?("password") || user.fetch("attributes").key?("encrypted_password") }
  end

  test "fictional display names are distinct while reader identities and login emails remain stable" do
    users = @plan.fetch("users")
    readers = users.select { |entry| entry.fetch("attributes").fetch("role") == "user" }

    assert_equal 31, users.map { |entry| entry.fetch("attributes").values_at("first_name", "last_name") }.uniq.length
    users.each do |entry|
      attributes = entry.fetch("attributes")
      assert_match(/\A[A-Z][a-z]+\z/, attributes.fetch("first_name"))
      assert_match(/\A[A-Z][a-z]+\z/, attributes.fetch("last_name"))
      assert_equal "#{attributes.fetch('first_name')}.#{attributes.fetch('last_name')}".downcase, attributes.fetch("nickname")
    end
    readers.each_with_index do |entry, index|
      identity = "reader#{format('%02d', index + 1)}"
      assert_equal identity, entry.fetch("identity")
      assert_equal "#{identity}@example.test", entry.fetch("attributes").fetch("email")
    end
    admin = users.find { |entry| entry.fetch("identity") == "admin" }
    assert_equal "reading_scenario_admin@example.test", admin.fetch("attributes").fetch("email")
  end

  test "invalid or ambiguous configured reference times are rejected" do
    [ "", "invalid", "2026-11-16T20:00:00", "2026-99-99T20:00:00Z" ].each do |value|
      variables = ENV.to_h.merge("READING_SCENARIO_AS_OF" => value)
      ENV.stub(:[], variables.method(:[])) do
        error = assert_raises(ArgumentError) { DevelopmentReadingScenarioPlan.new }
        assert_includes error.message, "READING_SCENARIO_AS_OF"
      end
    end
  end
end
