require "test_helper"

class ClubMessageTest < ActiveSupport::TestCase
  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @user = users(:leika)
  end

  test "persists a message with its club author and timestamps" do
    message = @book_club.club_messages.create!(user: @user, body: "What did you think of the ending?")

    assert_equal "What did you think of the ending?", message.reload.body
    assert_equal @book_club, message.book_club
    assert_equal @user, message.user
    assert_includes @user.club_messages, message
    assert_not_nil message.created_at
    assert_not_nil message.updated_at
  end

  test "requires a club and author" do
    message = ClubMessage.new(body: "A thought about the book")

    assert_not message.valid?
    assert_includes message.errors[:book_club], "must exist"
    assert_includes message.errors[:user], "must exist"
  end

  test "rejects missing empty and whitespace-only bodies without persisting" do
    [ nil, "", " \n\t " ].each do |body|
      message = @book_club.club_messages.build(user: @user, body: body)

      assert_no_difference "ClubMessage.count" do
        assert_not message.save
      end
      assert_includes message.errors[:body], "can't be blank"
    end
  end

  test "accepts exactly 1000 characters" do
    message = @book_club.club_messages.create!(user: @user, body: "a" * 1_000)

    assert_equal 1_000, message.reload.body.length
  end

  test "rejects more than 1000 characters without persisting" do
    message = @book_club.club_messages.build(user: @user, body: "a" * 1_001)

    assert_no_difference "ClubMessage.count" do
      assert_not message.save
    end
    assert_includes message.errors[:body], "is too long (maximum is 1000 characters)"
  end

  test "database rejects oversized bodies when validations are bypassed" do
    message = @book_club.club_messages.create!(user: @user, body: "Valid body")

    assert_raises ActiveRecord::StatementInvalid do
      ClubMessage.transaction(requires_new: true) do
        message.update_columns(body: "a" * 1_001)
      end
    end
    assert_equal "Valid body", message.reload.body
  end

  test "rolled back messages are not persisted" do
    assert_no_difference "ClubMessage.count" do
      ClubMessage.transaction(requires_new: true) do
        @book_club.club_messages.create!(user: @user, body: "Rolled back thought")
        raise ActiveRecord::Rollback
      end
    end
  end

  test "destroying a club removes its messages and preserves other clubs messages" do
    other_club = BookClub.create!(name: "Another circle")
    message = @book_club.club_messages.create!(user: @user, body: "This club's message")
    other_message = other_club.club_messages.create!(user: @user, body: "Another club's message")

    assert_difference "ClubMessage.count", -1 do
      @book_club.destroy!
    end
    assert_not ClubMessage.exists?(message.id)
    assert ClubMessage.exists?(other_message.id)
  end

  test "destroying an author removes their messages and preserves other authors messages" do
    author = users(:jaina)
    message = @book_club.club_messages.create!(user: author, body: "Author's message")
    other_message = @book_club.club_messages.create!(user: @user, body: "Another author's message")

    assert_difference "ClubMessage.count", -1 do
      author.destroy!
    end
    assert_not ClubMessage.exists?(message.id)
    assert ClubMessage.exists?(other_message.id)
  end
end
