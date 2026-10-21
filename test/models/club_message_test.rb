require "test_helper"

class ClubMessageTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @user = users(:leika)
  end

  test "discussion payload includes the author's uploaded avatar path" do
    @user.avatar.attach(io: File.open(file_fixture("cover_test.jpg")), filename: "avatar.jpg", content_type: "image/jpeg")
    message = create_message(body: "A thought")

    expected_path = Rails.application.routes.url_helpers.rails_blob_path(@user.avatar, only_path: true)
    assert_equal expected_path, message.discussion_payload.fetch(:author).fetch(:avatar_url)
  end

  test "body edits broadcast the updated post or reply payload after commit" do
    message = create_message(body: "Original thought")
    reply = create_message(parent: message, user: users(:jaina), body: "Original answer")
    stream = discussion_stream
    changes = [ { message: message, type: "message.updated" }, { message: reply, type: "reply.updated" } ]

    changes.each do |change|
      target = change.fetch(:message)
      assert_broadcasts stream, 1 do
        ClubMessage.transaction(requires_new: true) do
          target.update!(body: "Revised content")
          assert_no_broadcasts stream
        end
      end
      assert_broadcast_on stream, { type: change.fetch(:type), message: target.discussion_payload, total_posts: 1 }
    end
  end

  test "failed body edits emit no update and preserve the saved body" do
    message = create_message(body: "Original thought")

    assert_no_broadcasts discussion_stream do
      assert_not message.update(body: " ")
    end
    assert_equal "Original thought", message.reload.body
  end

  test "rolled back body edits emit no update and preserve the saved body" do
    message = create_message(body: "Original thought")

    assert_no_broadcasts discussion_stream do
      ClubMessage.transaction(requires_new: true) do
        message.update!(body: "Rolled back edit")
        raise ActiveRecord::Rollback
      end
    end
    assert_equal "Original thought", message.reload.body
  end

  test "unchanged bodies and timestamp-only updates emit no discussion update" do
    message = create_message(body: "Original thought")

    assert_no_broadcasts discussion_stream do
      message.update!(body: "Original thought")
      message.touch
    end
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

  test "a reply belongs to a post in the same club and appears in its replies" do
    post = create_message(body: "A discussion question")
    reply = create_message(parent: post, user: users(:jaina), body: "My answer")

    assert_equal post, reply.reload.parent
    assert_includes post.replies, reply
    assert_equal post.id, reply.discussion_payload.fetch(:parent_id)
    assert_nil post.discussion_payload.fetch(:parent_id)
  end

  test "replies to another club's posts are rejected without saving or broadcasting" do
    other_club = BookClub.create!(name: "Another circle")
    post = create_message(book_club: other_club, body: "Another club's question")
    reply = build_message(parent: post, user: @user, body: "Not allowed")

    assert_no_broadcasts discussion_stream do
      assert_no_difference "ClubMessage.count" do
        assert_not reply.save
      end
    end
    assert_includes reply.errors[:parent], "must belong to the same book club"
  end

  test "replies cannot have another level of replies" do
    post = create_message(body: "A discussion question")
    reply = create_message(parent: post, user: @user, body: "An answer")
    nested_reply = build_message(parent: reply, user: @user, body: "Too deeply nested")

    assert_no_difference "ClubMessage.count" do
      assert_not nested_reply.save
    end
    assert_includes nested_reply.errors[:parent], "would create nested replies"
  end

  test "a post that already has replies cannot become a reply" do
    post = create_message(body: "A discussion question")
    create_message(parent: post, user: @user, body: "An answer")
    another_post = create_message(body: "Another question")

    assert_not post.update(parent: another_post)

    assert_includes post.errors[:parent], "would create nested replies"
    assert_nil post.reload.parent_id
  end

  test "a message cannot be its own parent" do
    post = create_message(body: "A discussion question")

    assert_not post.update(parent: post)

    assert_includes post.errors[:parent], "cannot be the message itself"
    assert_nil post.reload.parent_id
  end

  test "a missing parent is rejected" do
    reply = build_message(body: "An answer")
    reply.parent_id = 0

    assert_not reply.valid?

    assert_includes reply.errors[:parent], "must exist"
  end

  test "the database rejects self references when validations are bypassed" do
    post = create_message(body: "A discussion question")

    assert_raises ActiveRecord::StatementInvalid do
      ClubMessage.transaction(requires_new: true) do
        post.update_columns(parent_id: post.id)
      end
    end
    assert_nil post.reload.parent_id
  end

  test "the database rejects missing parents when validations are bypassed" do
    post = create_message(body: "A discussion question")

    assert_raises ActiveRecord::InvalidForeignKey do
      ClubMessage.transaction(requires_new: true) do
        post.update_columns(parent_id: 0)
      end
    end
    assert_nil post.reload.parent_id
  end

  test "reply creation has its own event type and does not increase the post total" do
    post = create_message(body: "A discussion question")
    reply = build_message(parent: post, user: @user, body: "An answer")

    assert_broadcasts discussion_stream, 1 do
      reply.save!
    end

    assert_broadcast_on discussion_stream, { type: "reply.created", message: reply.discussion_payload, total_posts: 1 }
    assert_equal [ post.id ], @book_club.club_messages.top_level.pluck(:id)
  end

  test "rolled back replies are neither saved nor broadcast" do
    post = create_message(body: "A discussion question")

    assert_no_broadcasts discussion_stream do
      assert_no_difference "ClubMessage.count" do
        ClubMessage.transaction(requires_new: true) do
          create_message(parent: post, user: @user, body: "Rolled back answer")
          raise ActiveRecord::Rollback
        end
      end
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

  test "destroying a club removes its posts and replies and preserves other clubs messages" do
    other_club = BookClub.create!(name: "Another circle")
    message = create_message(body: "This club's message")
    reply = create_message(parent: message, user: users(:jaina), body: "A reply in this club")
    other_message = create_message(book_club: other_club, body: "Another club's message")

    assert_difference "ClubMessage.count", -2 do
      @book_club.destroy!
    end
    assert_not ClubMessage.exists?(message.id)
    assert_not ClubMessage.exists?(reply.id)
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

  test "removing a post clears its body and keeps its replies and post total" do
    post = create_message(body: "Original thought")
    reply = create_message(parent: post, body: "Retained answer")

    assert_no_difference "ClubMessage.count" do
      assert_broadcasts discussion_stream, 1 do
        payload = post.remove_from_discussion!
        assert_equal true, payload.fetch(:deleted)
        assert_equal "", payload.fetch(:body)
      end
    end

    assert post.reload.deleted?
    assert_equal "", post.body
    assert_equal post, reply.reload.parent
    assert_equal "Retained answer", reply.body
    assert_broadcast_on discussion_stream, { type: "message.deleted", message: post.discussion_payload, total_posts: 1 }

    deleted_at = post.deleted_at
    assert_no_broadcasts discussion_stream do
      post.remove_from_discussion!
    end
    assert_equal deleted_at, post.reload.deleted_at
  end

  test "removing a reply destroys only that reply and broadcasts an empty deleted payload" do
    post = create_message(body: "A question")
    reply = create_message(parent: post, body: "An answer")
    payload = nil

    assert_difference "ClubMessage.count", -1 do
      assert_broadcasts discussion_stream, 1 do
        payload = reply.remove_from_discussion!
      end
    end

    assert ClubMessage.exists?(post.id)
    assert_not ClubMessage.exists?(reply.id)
    assert_equal "", payload.fetch(:body)
    assert_equal true, payload.fetch(:deleted)
    assert_broadcast_on discussion_stream, { type: "reply.deleted", message: payload, total_posts: 1 }
  end

  test "rolled back post and reply removals preserve content and emit no deletion events" do
    post = create_message(body: "Original thought")
    reply = create_message(parent: post, body: "Original answer")

    assert_no_broadcasts discussion_stream do
      ClubMessage.transaction(requires_new: true) do
        reply.remove_from_discussion!
        post.remove_from_discussion!
        assert_no_broadcasts discussion_stream
        raise ActiveRecord::Rollback
      end
    end

    assert_equal "Original thought", post.reload.body
    assert_not post.deleted?
    assert_equal "Original answer", reply.reload.body
  end

  test "deleted posts reject new replies but existing replies remain editable" do
    post = create_message(body: "A question")
    reply = create_message(parent: post, body: "An answer")
    post.remove_from_discussion!
    new_reply = build_message(parent: post, body: "A late answer")

    assert_no_difference "ClubMessage.count" do
      assert_not new_reply.save
    end
    assert_includes new_reply.errors[:parent], "cannot be a deleted post"
    assert reply.update(body: "Revised answer")
    assert_equal "Revised answer", reply.reload.body
  end

  test "validation and database constraints reject invalid deleted post states" do
    post = create_message(body: "A question")
    reply = create_message(parent: post, body: "An answer")
    targets = [ post, reply ]

    targets.each do |message|
      assert_not message.update(deleted_at: Time.current)
      message.reload
      assert_raises ActiveRecord::StatementInvalid do
        ClubMessage.transaction(requires_new: true) do
          message.update_columns(deleted_at: Time.current)
        end
      end
      assert_not message.reload.deleted?
    end

    assert_raises ActiveRecord::StatementInvalid do
      ClubMessage.transaction(requires_new: true) do
        reply.update_columns(body: "", deleted_at: Time.current)
      end
    end
    assert_equal "An answer", reply.reload.body
  end

  test "a deleted post with no replies is retained but excluded from visible posts" do
    post = create_message(body: "A thought")
    post.remove_from_discussion!

    assert ClubMessage.exists?(post.id)
    assert_empty @book_club.club_messages.visible_posts
    assert_equal 0, post.discussion_payload.fetch(:replies_count)
    assert_broadcast_on discussion_stream, { type: "message.deleted", message: post.discussion_payload, total_posts: 0 }
  end

  test "only deleting the last reply hides a deleted parent and broadcasts its empty reply count after commit" do
    post = create_message(body: "A question")
    first_reply = create_message(parent: post, body: "First answer")
    last_reply = create_message(parent: post, body: "Last answer")
    post.remove_from_discussion!
    first_reply.remove_from_discussion!
    assert_includes @book_club.club_messages.visible_posts, post

    assert_broadcasts discussion_stream, 2 do
      ClubMessage.transaction(requires_new: true) do
        last_reply.remove_from_discussion!
        assert_no_broadcasts discussion_stream
      end
    end

    assert ClubMessage.exists?(post.id)
    assert_empty @book_club.club_messages.visible_posts
    assert_equal 0, post.reload.discussion_payload.fetch(:replies_count)
    assert_broadcast_on discussion_stream, { type: "message.deleted", message: post.discussion_payload, total_posts: 0 }
  end

  test "rolling back the final reply deletion keeps the deleted post visible and emits no hiding event" do
    post = create_message(body: "A question")
    reply = create_message(parent: post, body: "Last answer")
    post.remove_from_discussion!

    assert_no_broadcasts discussion_stream do
      ClubMessage.transaction(requires_new: true) do
        reply.remove_from_discussion!
        raise ActiveRecord::Rollback
      end
    end

    assert ClubMessage.exists?(reply.id)
    assert_includes @book_club.club_messages.visible_posts, post
  end

  private

  def build_message(body:, user: @user, book_club: @book_club, parent: nil)
    book_club.club_messages.build(user: user, body: body, parent: parent)
  end

  def create_message(body:, user: @user, book_club: @book_club, parent: nil)
    message = build_message(body: body, user: user, book_club: book_club, parent: parent)
    message.save!
    message
  end

  def discussion_stream(book_club = @book_club)
    ClubDiscussionChannel.broadcasting_for(book_club)
  end
end
