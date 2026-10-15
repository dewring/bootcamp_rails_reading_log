require "test_helper"

class Admin::BookClubPolicyTest < ActiveSupport::TestCase
  test "workspace permissions are restricted to admins even when a reader owns the club" do
    club = BookClub.create!(name: "Owner Club")
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    [ nil, users(:leika), users(:jaina) ].each do |reader|
      policy = Admin::BookClubPolicy.new(reader, club)
      refute policy.index?
      refute policy.create?
      refute policy.update?
      refute policy.destroy?
      assert_empty Admin::BookClubPolicy::Scope.new(reader, BookClub.all).resolve
    end
    policy = Admin::BookClubPolicy.new(users(:admin), club)
    assert policy.index?
    assert policy.create?
    assert policy.update?
    assert policy.destroy?
    assert_equal [ club ], Admin::BookClubPolicy::Scope.new(users(:admin), BookClub.all).resolve.to_a
  end
end
