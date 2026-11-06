require "test_helper"

class ReactionPolicyTest < ActiveSupport::TestCase
  setup do
    @reader = users(:leika)
    @club = BookClub.create!(name: "Reaction permissions")
    @membership = @club.book_club_memberships.create!(user: @reader, role: "member")
    @message = @club.club_messages.create!(user: @reader, body: "A discussion thought")
    @reactions = [
      Reaction.new(user: @reader, book: books(:refactoring), kind: "like"),
      ReviewReaction.new(user: @reader, review: reviews(:review1), kind: "like"),
      ClubMessageReaction.new(user: @reader, club_message: @message, kind: "like")
    ]
  end

  test "Pundit uses the policy for each concrete reaction model" do
    assert_instance_of ReactionPolicy, Pundit.policy!(@reader, @reactions.first)
    assert_instance_of ReviewReactionPolicy, Pundit.policy!(@reader, @reactions.second)
    assert_instance_of ClubMessageReactionPolicy, Pundit.policy!(@reader, @reactions.third)
  end

  test "active owners can select change and clear their own reactions" do
    @reactions.each do |reaction|
      policy = Pundit.policy!(@reader, reaction)

      assert policy.show?
      assert policy.create?
      assert policy.update?
      assert policy.destroy?
    end
  end

  test "guests can read public book and review counts but cannot mutate reactions" do
    assert Pundit.policy!(nil, @reactions.first).show?
    assert Pundit.policy!(nil, @reactions.second).show?
    assert_not Pundit.policy!(nil, @reactions.third).show?
    @reactions.each do |reaction|
      policy = Pundit.policy!(nil, reaction)

      assert_not policy.create?
      assert_not policy.update?
      assert_not policy.destroy?
    end
  end

  test "invited and suspended owners cannot mutate reactions" do
    [ "invited", "suspended" ].each do |status|
      @reader.update!(account_status: status)
      @reactions.each do |reaction|
        policy = Pundit.policy!(@reader, reaction)

        assert_not policy.create?
        assert_not policy.update?
        assert_not policy.destroy?
      end
    end
  end

  test "another reader or admin cannot mutate someone elses reaction" do
    [ users(:jaina), users(:admin) ].each do |viewer|
      @reactions.each do |reaction|
        policy = Pundit.policy!(viewer, reaction)

        assert_not policy.create?
        assert_not policy.update?
        assert_not policy.destroy?
      end
    end
  end

  test "nonmembers and former members cannot read or react to Discussion messages" do
    reaction = ClubMessageReaction.new(user: users(:jaina), club_message: @message, kind: "love")
    assert_not Pundit.policy!(users(:jaina), reaction).show?
    assert_not Pundit.policy!(users(:jaina), reaction).create?
    @membership.destroy!

    policy = Pundit.policy!(@reader, @reactions.third)
    assert_not policy.show?
    assert_not policy.update?
    assert_not policy.destroy?
  end

  test "authorized nonmember admins can react to Discussion messages" do
    admin = users(:admin)
    reaction = ClubMessageReaction.new(user: admin, club_message: @message, kind: "love")
    policy = Pundit.policy!(admin, reaction)

    assert policy.show?
    assert policy.create?
  end

  test "a deleted post cannot receive reactions but its visible replies can" do
    reply = @club.club_messages.create!(parent: @message, user: @reader, body: "An answer")
    reply_reaction = ClubMessageReaction.new(user: @reader, club_message: reply, kind: "love")
    @message.remove_from_discussion!

    assert_not Pundit.policy!(@reader, @reactions.third).create?
    assert Pundit.policy!(@reader, reply_reaction).create?
  end

  test "a missing target denies reads and mutations" do
    [ Reaction, ReviewReaction, ClubMessageReaction ].each do |model|
      policy = Pundit.policy!(@reader, model.new(user: @reader, kind: "like"))

      assert_not policy.show?
      assert_not policy.create?
      assert_not policy.destroy?
    end
  end

  test "book visibility denial also denies reaction mutations" do
    target_policy = Object.new
    target_policy.define_singleton_method(:show?) { false }
    policy = ReactionPolicy.new(@reader, @reactions.first)

    Pundit.stub(:policy!, target_policy) do
      assert_not policy.show?
      assert_not policy.create?
      assert_not policy.destroy?
    end
  end

  test "reaction scopes expose only the requesting users choices" do
    @reactions.each do |reaction|
      reaction.save!
      other = reaction.dup
      other.user = users(:jaina)
      other.save!

      assert_equal [ reaction.id ], Pundit.policy_scope!(@reader, reaction.class).pluck(:id)
      assert_equal [ other.id ], Pundit.policy_scope!(users(:jaina), reaction.class).pluck(:id)
      assert_empty Pundit.policy_scope!(nil, reaction.class)
    end
  end
end
