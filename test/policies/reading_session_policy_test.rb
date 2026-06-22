require "test_helper"
class ReadingSessionPolicyTest < ActiveSupport::TestCase
  test "logged-in user can index reading sessions" do
    assert ReadingSessionPolicy.new(users(:leika), ReadingSession).index?
  end

  test "admin can index reading sessions" do
    assert ReadingSessionPolicy.new(users(:admin), ReadingSession).index?
  end

  test "owner can show their own session" do
    assert ReadingSessionPolicy.new(users(:leika), reading_sessions(:one)).show?
  end

  test "non-owner cannot show someone else's session" do
    refute ReadingSessionPolicy.new(users(:jaina), reading_sessions(:one)).show?
  end

  test "admin can show any session" do
    assert ReadingSessionPolicy.new(users(:admin), reading_sessions(:one)).show?
  end

  test "logged-in user can create a reading session" do
    assert ReadingSessionPolicy.new(users(:leika), ReadingSession.new).create?
  end
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
