require "test_helper"

class ClubMessagePolicyTest < ActiveSupport::TestCase
  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @owner = users(:leika)
    @author = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @author, role: "member")
    @message = @book_club.club_messages.create!(user: @author, body: "A discussion thought")
  end

  test "members can read history view messages and post" do
    users = [ @owner, @author ]

    users.each do |user|
      policy = ClubMessagePolicy.new(user, @message)

      assert policy.index?
      assert policy.show?
      assert policy.create?
    end
  end

  test "nonmember admin can read history and view messages but cannot post" do
    policy = ClubMessagePolicy.new(@admin, @message)

    assert policy.index?
    assert policy.show?
    refute policy.create?
  end

  test "admin can post after joining the club but cannot edit another authors message" do
    @book_club.book_club_memberships.create!(user: @admin, role: "member")
    policy = ClubMessagePolicy.new(@admin, @message)

    assert policy.create?
    refute policy.update?
  end

  test "former member admin retains moderation access but cannot edit their own message" do
    membership = @book_club.book_club_memberships.create!(user: @admin, role: "member")
    message = @book_club.club_messages.create!(user: @admin, body: "Admin's thought")
    policy = ClubMessagePolicy.new(@admin, message)
    assert policy.update?

    membership.destroy!

    assert policy.index?
    assert policy.show?
    assert policy.destroy?
    refute policy.create?
    refute policy.update?
  end

  test "guest has no message permissions" do
    policy = ClubMessagePolicy.new(nil, @message)

    refute policy.index?
    refute policy.show?
    refute policy.create?
    refute policy.update?
    refute policy.destroy?
  end

  test "current member author can edit and delete their own message" do
    policy = ClubMessagePolicy.new(@author, @message)

    assert policy.edit?
    assert policy.update?
    assert policy.destroy?
  end

  test "club owner can delete but cannot edit another authors message" do
    policy = ClubMessagePolicy.new(@owner, @message)

    assert policy.destroy?
    refute policy.edit?
    refute policy.update?
  end

  test "admin can delete but cannot edit another authors message without club membership" do
    policy = ClubMessagePolicy.new(@admin, @message)

    assert policy.destroy?
    refute policy.edit?
    refute policy.update?
  end

  test "ordinary member cannot edit or delete another authors message" do
    message = @book_club.club_messages.create!(user: @owner, body: "Owner's thought")
    policy = ClubMessagePolicy.new(@author, message)

    refute policy.update?
    refute policy.destroy?
  end

  test "former member author cannot read post edit or delete" do
    policy = ClubMessagePolicy.new(@author, @message)
    @book_club.book_club_memberships.find_by!(user: @author).destroy!

    refute policy.index?
    refute policy.show?
    refute policy.create?
    refute policy.update?
    refute policy.destroy?
  end

  test "owning another club does not grant message deletion permission" do
    other_club = BookClub.create!(name: "Another circle")
    other_message = other_club.club_messages.create!(user: @author, body: "Private thought")
    policy = ClubMessagePolicy.new(@owner, other_message)

    refute policy.show?
    refute policy.update?
    refute policy.destroy?
  end

  test "scope returns only messages from clubs the user belongs to" do
    other_club = BookClub.create!(name: "Another circle")
    other_club.club_messages.create!(user: @author, body: "Another club's thought")

    assert_equal [ @message ], ClubMessagePolicy::Scope.new(@author, ClubMessage.all).resolve.to_a
  end

  test "guest has an empty history scope" do
    assert_empty ClubMessagePolicy::Scope.new(nil, ClubMessage.all).resolve
  end

  test "nonmember admin history scope includes messages from every club" do
    other_club = BookClub.create!(name: "Another circle")
    other_message = other_club.club_messages.create!(user: @author, body: "Another club's thought")
    messages = ClubMessagePolicy::Scope.new(@admin, ClubMessage.all).resolve

    assert_equal [ @message.id, other_message.id ].sort, messages.pluck(:id).sort
  end
end
