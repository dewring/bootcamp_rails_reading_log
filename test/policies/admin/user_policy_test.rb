require "test_helper"

class Admin::UserPolicyTest < ActiveSupport::TestCase
  test "only admins may browse invite and edit accounts" do
    [ nil, users(:leika) ].each do |viewer|
      policy = Admin::UserPolicy.new(viewer, users(:jaina))
      refute policy.index?
      refute policy.create?
      refute policy.update?
      assert_empty Admin::UserPolicy::Scope.new(viewer, User.all).resolve
    end
    policy = Admin::UserPolicy.new(users(:admin), users(:leika))
    assert policy.index?
    assert policy.create?
    assert policy.update?
    assert policy.update_status?
    assert_equal User.count, Admin::UserPolicy::Scope.new(users(:admin), User.all).resolve.count
  end

  test "admins and club owners cannot be deleted" do
    policy = Admin::UserPolicy.new(users(:admin), users(:admin))
    refute policy.update_status?
    refute policy.destroy?
    club = BookClub.create!(name: "Owned")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    refute Admin::UserPolicy.new(users(:admin), users(:leika)).destroy?
    assert Admin::UserPolicy.new(users(:admin), users(:jaina)).destroy?
  end
end
