require "test_helper"

class ClubMessageTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @user = users(:leika)
  end

  test "persists a message with its club author and timestamps" do
    message = create_message(body: "What did you think of the ending?")

    assert_equal "What did you think of the ending?", message.reload.body
    assert_equal @book_club, message.book_club
    assert_equal @user, message.user
    assert_includes @user.club_messages, message
    assert_not_nil message.created_at
    assert_not_nil message.updated_at
  end

  test "creation broadcasts the same message payload used by HTTP" do
    message = build_message(body: "A new thought")
    stream = discussion_stream

    assert_broadcasts stream, 1 do
      message.save!
    end

    assert_broadcast_on stream, { type: "message.created", message: message.discussion_payload, total_posts: 1 }
  end

  test "creation waits until the transaction commits before broadcasting" do
    stream = discussion_stream

    assert_broadcasts stream, 1 do
      ClubMessage.transaction(requires_new: true) do
        create_message(body: "Committed thought")

        assert_no_broadcasts stream
      end
    end
  end

  test "failed validation does not broadcast" do
    message = build_message(body: "")
    stream = discussion_stream

    assert_no_broadcasts stream do
      assert_not message.save
    end
  end

  test "creation does not broadcast to another club" do
    other_club = BookClub.create!(name: "Another circle")
    other_stream = discussion_stream(other_club)

    assert_no_broadcasts other_stream do
      create_message(body: "This club's thought")
    end
  end

  test "requires a club and author" do
    message = ClubMessage.new(body: "A thought about the book")

    assert_not message.valid?
    assert_includes message.errors[:book_club], "must exist"
    assert_includes message.errors[:user], "must exist"
  end

  test "rejects missing empty and whitespace-only bodies without persisting" do
    [ nil, "", " \n\t " ].each do |body|
      message = build_message(body: body)

      assert_no_difference "ClubMessage.count" do
        assert_not message.save
      end
      assert_includes message.errors[:body], "can't be blank"
    end
  end

  test "accepts exactly 1000 characters" do
    message = create_message(body: "a" * 1_000)

    assert_equal 1_000, message.reload.body.length
  end

  test "rejects more than 1000 characters without persisting" do
    message = build_message(body: "a" * 1_001)

    assert_no_difference "ClubMessage.count" do
      assert_not message.save
    end
    assert_includes message.errors[:body], "is too long (maximum is 1000 characters)"
  end

  test "database rejects oversized bodies when validations are bypassed" do
    message = create_message(body: "Valid body")

    assert_raises ActiveRecord::StatementInvalid do
      ClubMessage.transaction(requires_new: true) do
        message.update_columns(body: "a" * 1_001)
      end
    end
    assert_equal "Valid body", message.reload.body
  end

  test "rolled back messages are not persisted" do
    stream = discussion_stream

    assert_no_broadcasts stream do
      assert_no_difference "ClubMessage.count" do
        ClubMessage.transaction(requires_new: true) do
          create_message(body: "Rolled back thought")
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test "destroying a club removes its messages and preserves other clubs messages" do
    other_club = BookClub.create!(name: "Another circle")
    message = create_message(body: "This club's message")
    other_message = create_message(book_club: other_club, body: "Another club's message")

    assert_difference "ClubMessage.count", -1 do
      @book_club.destroy!
    end
    assert_not ClubMessage.exists?(message.id)
    assert ClubMessage.exists?(other_message.id)
  end

  test "destroying an author removes their messages and preserves other authors messages" do
    author = users(:jaina)
    message = create_message(user: author, body: "Author's message")
    other_message = create_message(body: "Another author's message")

    assert_difference "ClubMessage.count", -1 do
      author.destroy!
    end
    assert_not ClubMessage.exists?(message.id)
    assert ClubMessage.exists?(other_message.id)
  end

  private

  def build_message(body:, user: @user, book_club: @book_club)
    book_club.club_messages.build(user: user, body: body)
  end

  def create_message(body:, user: @user, book_club: @book_club)
    message = build_message(body: body, user: user, book_club: book_club)
    message.save!
    message
  end

  def discussion_stream(book_club = @book_club)
    ClubDiscussionChannel.broadcasting_for(book_club)
  end
end
