require "test_helper"

class ReactionTypeTest < ActiveSupport::TestCase
  test "a data added kind accepts emoji made from multiple Unicode code points" do
    type = ReactionType.create!(key: "family", label: "Family", emoji: "👨‍👩‍👧‍👦", enabled: true)
    reaction = Reaction.create!(user: users(:leika), book: books(:refactoring), kind: type.key)

    assert_equal type, reaction.reaction_type
    assert_equal "👨‍👩‍👧‍👦", type.reload.emoji
  end

  test "key label emoji and a boolean enabled value are required" do
    [ :key, :label, :emoji ].each do |attribute|
      type = ReactionType.new(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: true)
      type[attribute] = " "

      assert_not type.valid?
      assert_includes type.errors[attribute], "can't be blank"
    end
    assert_not ReactionType.new(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: nil).valid?
    assert ReactionType.new(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: false).valid?
  end

  test "catalog keys are unique and cannot change after creation" do
    type = reaction_types(:like)

    assert_not ReactionType.new(key: type.key, label: "Duplicate", emoji: "🎉").valid?
    assert_not type.update(key: "renamed")
    assert_equal "like", type.reload.key
  end

  test "database uniqueness rejects duplicate catalog keys" do
    duplicate = ReactionType.new(key: "like", label: "Duplicate", emoji: "🎉")

    assert_raises(ActiveRecord::RecordNotUnique) do
      ReactionType.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end
  end

  test "database constraints reject blank catalog text and null enabled values" do
    [ :key, :label, :emoji, :enabled ].each do |attribute|
      type = ReactionType.new(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: true)
      type[attribute] = attribute == :enabled ? nil : " "

      assert_raises(ActiveRecord::StatementInvalid) do
        ReactionType.transaction(requires_new: true) { type.save!(validate: false) }
      end
    end
  end

  test "account deletion removes the users reactions across all three target types" do
    reader = User.create!(first_name: "Reaction", last_name: "Reader", email: "reaction-reader@example.test", nickname: "reaction_reader", password: "test-password-143")
    club = BookClub.create!(name: "Account deletion discussion")
    message = ClubMessage.create!(book_club: club, user: users(:admin), body: "A discussion post")
    book_reaction = Reaction.create!(user: reader, book: books(:refactoring), kind: "like")
    review_reaction = ReviewReaction.create!(user: reader, review: reviews(:review1), kind: "love")
    message_reaction = ClubMessageReaction.create!(user: reader, club_message: message, kind: "wow")

    reader.destroy!

    assert_not Reaction.exists?(book_reaction.id)
    assert_not ReviewReaction.exists?(review_reaction.id)
    assert_not ClubMessageReaction.exists?(message_reaction.id)
    assert Review.exists?(reviews(:review1).id)
    assert ClubMessage.exists?(message.id)
  end
end
