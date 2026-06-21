require "test_helper"
class ReadingSessionPolicyTest < ActiveSupport::TestCase
  test "owner can update their own session" do
    assert ReadingSessionPolicy.new(users(:leika), reading_sessions(:one)).update?
  end

  test "non-owner cannot update someone else's session" do
    refute ReadingSessionPolicy.new(users(:admin), reading_sessions(:one)).update?
  end

  test "owner can destroy their own session" do
    assert ReadingSessionPolicy.new(users(:leika), reading_sessions(:one)).destroy?
  end

  test "non-owner cannot destroy someone else's session" do
    refute ReadingSessionPolicy.new(users(:admin), reading_sessions(:one)).destroy?
  end
end
