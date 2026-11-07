require "test_helper"
require_relative "../support/reaction_model_tests"

class ClubMessageReactionTest < ActiveSupport::TestCase
  include ReactionModelTests

  setup do
    club = BookClub.create!(name: "Reaction discussion")
    @target = ClubMessage.create!(book_club: club, user: users(:leika), body: "A discussion post")
  end

  test "a reply has its own reaction identity separate from its parent" do
    reply = ClubMessage.create!(book_club: @target.book_club, parent: @target, user: users(:jaina), body: "An answer")
    post_reaction = ClubMessageReaction.create!(reaction_attributes)
    reply_reaction = ClubMessageReaction.create!(user: users(:leika), club_message: reply, kind: "love")

    assert_equal [ post_reaction.id ], @target.reactions.pluck(:id)
    assert_equal [ reply_reaction.id ], reply.reactions.pluck(:id)
  end

  test "soft deletion removes post reactions and preserves replies and their reactions" do
    reply = ClubMessage.create!(book_club: @target.book_club, parent: @target, user: users(:jaina), body: "An answer")
    post_reaction = ClubMessageReaction.create!(reaction_attributes)
    reply_reaction = ClubMessageReaction.create!(user: users(:leika), club_message: reply, kind: "love")

    @target.remove_from_discussion!

    assert @target.reload.deleted?
    assert_not ClubMessageReaction.exists?(post_reaction.id)
    assert ClubMessageReaction.exists?(reply_reaction.id)
    assert reply.reload.persisted?
    assert_not ClubMessageReaction.new(reaction_attributes).valid?
  end

  test "rolling back soft deletion restores both the post and its reactions" do
    reaction = ClubMessageReaction.create!(reaction_attributes)

    ClubMessage.transaction(requires_new: true) do
      @target.remove_from_discussion!
      raise ActiveRecord::Rollback
    end

    assert_not @target.reload.deleted?
    assert ClubMessageReaction.exists?(reaction.id)
  end

  private

  def reaction_model
    ClubMessageReaction
  end

  def reaction_target
    @target
  end

  def target_foreign_key
    :club_message_id
  end
end
