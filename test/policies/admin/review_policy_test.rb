require "test_helper"

class Admin::ReviewPolicyTest < ActiveSupport::TestCase
  test "only admins can browse or delete community reviews" do
    [ nil, users(:leika) ].each do |reader|
      policy = Admin::ReviewPolicy.new(reader, reviews(:review2))
      refute policy.index?
      refute policy.destroy?
      assert_empty Admin::ReviewPolicy::Scope.new(reader, Review.all).resolve
    end

    policy = Admin::ReviewPolicy.new(users(:admin), reviews(:review2))
    assert policy.index?
    assert policy.destroy?
    refute policy.update?
    assert_equal Review.count, Admin::ReviewPolicy::Scope.new(users(:admin), Review.all).resolve.count
  end
end
