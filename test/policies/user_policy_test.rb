require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  test "owner can view and update themself" do
    user = users(:leika)
    policy = UserPolicy.new(user, user)

    assert policy.show?
    assert policy.update?
  end

  test "regular user cannot update another user" do
    refute UserPolicy.new(users(:leika), users(:jaina)).update?
  end

  test "admin can update another user" do
    assert UserPolicy.new(users(:admin), users(:leika)).update?
  end

  test "regular user scope only includes self" do
    resolved = UserPolicy::Scope.new(users(:leika), User.all).resolve

    assert_equal [ users(:leika).id ], resolved.ids
  end

  test "admin scope includes all users" do
    resolved = UserPolicy::Scope.new(users(:admin), User.all).resolve

    assert_equal User.count, resolved.count
  end
end
