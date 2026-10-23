require "test_helper"

class ClubDiscussionChannelTest < ActionCable::Channel::TestCase
  setup do
    Rack::Attack.reset!
    @book_club = BookClub.create!(name: "Discussion circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
    presence = instance_double(ClubPresence, renew_connection: [], active_member_ids: [])
    allow(ClubPresence).to receive(:new).and_return(presence)
  end

  teardown do
    Rack::Attack.reset!
  end

  test "authors owners and nonmember admins can delete posts and replies" do
    actors = [ @member, @owner, @admin ]

    actors.each do |actor|
      post = @book_club.club_messages.create!(user: @member, body: "A question")
      reply = @book_club.club_messages.create!(parent: post, user: @member, body: "An answer")
      stub_connection current_user: actor
      subscribe book_club_id: @book_club.id

      assert_no_difference "ClubMessage.count" do
        perform :delete_message, request_id: "delete-post", message_id: post.id
      end
      assert post.reload.deleted?
      assert_equal "", post.body
      assert_equal post, reply.reload.parent
      assert_equal "delete.saved", transmissions.last.fetch("type")
      assert_equal post.discussion_payload.as_json, transmissions.last.fetch("message")

      assert_difference "ClubMessage.count", -1 do
        perform :delete_message, request_id: "delete-reply", message_id: reply.id
      end
      assert_equal "delete.saved", transmissions.last.fetch("type")
      assert_equal true, transmissions.last.fetch("message").fetch("deleted")
      assert_equal "", transmissions.last.fetch("message").fetch("body")
      assert_not ClubMessage.exists?(reply.id)
    end
  end

  test "ordinary members cannot delete another author's content" do
    post = @book_club.club_messages.create!(user: @owner, body: "Owner's thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_no_broadcasts @book_club do
      perform :delete_message, request_id: "forbidden-delete", message_id: post.id
    end
    assert_equal "delete.rejected", transmissions.last.fetch("type")
    assert_equal "forbidden", transmissions.last.fetch("error")
    assert_equal "Owner's thought", post.reload.body
  end

  test "deletion rejects cross-club and invalid message ids" do
    other_club = BookClub.create!(name: "Another circle")
    post = other_club.club_messages.create!(user: @member, body: "Private thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    message_ids = [ post.id, nil, -1, 0, "invalid" ]

    message_ids.each do |message_id|
      assert_no_difference "ClubMessage.count" do
        perform :delete_message, request_id: "invalid-delete", message_id: message_id
      end
      assert_equal "delete.rejected", transmissions.last.fetch("type")
      assert_equal "not_found", transmissions.last.fetch("error")
    end
    assert_equal "Private thought", post.reload.body
  end

  test "invalid request ids cannot delete messages" do
    post = @book_club.club_messages.create!(user: @member, body: "A thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    request_ids = [ nil, "", "a" * 65, 123 ]

    request_ids.each do |request_id|
      perform :delete_message, request_id: request_id, message_id: post.id
    end
    assert_empty transmissions
    assert_not post.reload.deleted?
  end

  test "removed members cannot delete their own messages" do
    post = @book_club.club_messages.create!(user: @member, body: "A thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    perform :delete_message, request_id: "former-member-delete", message_id: post.id

    assert_equal "access.revoked", transmissions.last.fetch("type")
    assert_not post.reload.deleted?
  end

  test "deleted posts reject edits and new replies" do
    post = @book_club.club_messages.create!(user: @member, body: "A thought")
    post.remove_from_discussion!
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_no_broadcasts @book_club do
      perform :update_message, request_id: "deleted-edit", message_id: post.id, body: "Restored thought"
    end
    assert_equal "forbidden", transmissions.last.fetch("error")
    assert_no_difference "ClubMessage.count" do
      perform :post_reply, request_id: "deleted-reply", parent_id: post.id, body: "A late answer"
    end
    assert_equal "not_found", transmissions.last.fetch("error")
    assert_equal "", post.reload.body
  end

  test "an author can edit their own post without creating another message" do
    message = @book_club.club_messages.create!(user: @member, body: "Original thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_no_difference "ClubMessage.count" do
      perform :update_message, request_id: "edit-post", message_id: message.id, body: "Revised thought"
    end

    assert_equal "Revised thought", message.reload.body
    assert_equal "edit.saved", transmissions.last.fetch("type")
    assert_equal "edit-post", transmissions.last.fetch("request_id")
    assert_equal message.discussion_payload.as_json, transmissions.last.fetch("message")
  end

  test "an author can edit their own reply while preserving its parent" do
    parent = @book_club.club_messages.create!(user: @owner, body: "A question")
    reply = @book_club.club_messages.create!(parent: parent, user: @member, body: "Original answer")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    perform :update_message, request_id: "edit-reply", message_id: reply.id, body: "Revised answer"

    assert_equal "Revised answer", reply.reload.body
    assert_equal parent, reply.parent
    assert_equal "edit.saved", transmissions.last.fetch("type")
  end

  test "club owners and joined admins cannot edit another author's post or reply" do
    message = @book_club.club_messages.create!(user: @member, body: "Original thought")
    reply = @book_club.club_messages.create!(parent: message, user: @member, body: "Original answer")
    @book_club.book_club_memberships.create!(user: @admin, role: "member")
    viewers = [ @owner, @admin ]
    messages = [ message, reply ]

    viewers.each do |viewer|
      stub_connection current_user: viewer
      subscribe book_club_id: @book_club.id
      messages.each do |target|
        assert_no_broadcasts @book_club do
          perform :update_message, request_id: "forbidden-edit", message_id: target.id, body: "Changed by someone else"
        end
        assert_equal "edit.rejected", transmissions.last.fetch("type")
        assert_equal "forbidden", transmissions.last.fetch("error")
      end
    end
    assert_equal "Original thought", message.reload.body
    assert_equal "Original answer", reply.reload.body
  end

  test "a nonmember admin cannot edit even their own message" do
    message = @book_club.club_messages.create!(user: @admin, body: "Original thought")
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id

    assert_no_broadcasts @book_club do
      perform :update_message, request_id: "admin-edit", message_id: message.id, body: "Revised thought"
    end

    assert_equal "forbidden", transmissions.last.fetch("error")
    assert_equal "Original thought", message.reload.body
  end

  test "membership removal after subscribing prevents editing and revokes access" do
    message = @book_club.club_messages.create!(user: @member, body: "Original thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    perform :update_message, request_id: "former-member-edit", message_id: message.id, body: "Revised thought"

    assert_equal "access.revoked", transmissions.last.fetch("type")
    assert_equal "Original thought", message.reload.body
  end

  test "edits reject messages from another club and invalid message ids" do
    other_club = BookClub.create!(name: "Another discussion circle")
    other_message = other_club.club_messages.create!(user: @member, body: "Another club's thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    message_ids = [ other_message.id, nil, -1, 0, "invalid" ]

    message_ids.each do |message_id|
      assert_no_broadcasts @book_club do
        perform :update_message, request_id: "missing-edit", message_id: message_id, body: "Revised thought"
      end
      assert_equal "edit.rejected", transmissions.last.fetch("type")
      assert_equal "not_found", transmissions.last.fetch("error")
    end
    assert_equal "Another club's thought", other_message.reload.body
  end

  test "invalid edit bodies leave the saved body unchanged and emit no broadcast" do
    message = @book_club.club_messages.create!(user: @member, body: "Original thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    bodies = [ nil, "", " ", "a" * 1_001, { text: "Wrong type" } ]

    bodies.each do |body|
      assert_no_broadcasts @book_club do
        perform :update_message, request_id: "invalid-edit", message_id: message.id, body: body
      end
      assert_equal "edit.rejected", transmissions.last.fetch("type")
      assert transmissions.last.fetch("errors").fetch("body").any?
      assert_equal "Original thought", message.reload.body
    end
  end

  test "editing ignores spoofed author club parent and timestamps" do
    message = @book_club.club_messages.create!(user: @member, body: "Original thought")
    parent = @book_club.club_messages.create!(user: @owner, body: "Another question")
    original_created_at = message.created_at
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    perform :update_message, request_id: "safe-edit", message_id: message.id, body: "Revised thought",
      user_id: @admin.id, book_club_id: -1, parent_id: parent.id,
      created_at: "2000-01-01T00:00:00Z", updated_at: "2000-01-01T00:00:00Z"

    assert_equal "edit.saved", transmissions.last.fetch("type")
    assert_equal "Revised thought", message.reload.body
    assert_equal @member, message.user
    assert_equal @book_club, message.book_club
    assert_nil message.parent_id
    assert_equal original_created_at, message.created_at
    assert_not_equal 2000, message.updated_at.year
  end

  test "invalid request ids cannot edit messages" do
    message = @book_club.club_messages.create!(user: @member, body: "Original thought")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    request_ids = [ nil, "", "a" * 65, 123 ]

    request_ids.each do |request_id|
      assert_no_broadcasts @book_club do
        perform :update_message, request_id: request_id, message_id: message.id, body: "Revised thought"
      end
    end
    assert_empty transmissions
    assert_equal "Original thought", message.reload.body
  end

  test "reply submission derives author club and parent from the subscribed club" do
    parent = @book_club.club_messages.create!(user: @owner, body: "A question")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_difference "ClubMessage.count", 1 do
      perform :post_reply, request_id: "reply-1", parent_id: parent.id, body: "An answer", user_id: @admin.id, book_club_id: -1
    end

    reply = parent.replies.last
    assert_equal @member, reply.user
    assert_equal @book_club, reply.book_club
    assert_equal "reply.saved", transmissions.last.fetch("type")
    assert_equal reply.discussion_payload.as_json, transmissions.last.fetch("message")
    assert_equal 1, transmissions.last.fetch("total_posts")
  end

  test "replies cannot target another club a reply or an invalid parent id" do
    parent = @book_club.club_messages.create!(user: @owner, body: "A question")
    reply = parent.replies.create!(book_club: @book_club, user: @owner, body: "An answer")
    other_club = BookClub.create!(name: "Another circle")
    other_post = other_club.club_messages.create!(user: @owner, body: "Private question")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    [ other_post.id, reply.id, nil, "invalid", -1 ].each do |parent_id|
      assert_no_difference "ClubMessage.count" do
        assert_no_broadcasts @book_club do
          perform :post_reply, request_id: "invalid-parent", parent_id: parent_id, body: "An answer"
        end
      end
      assert_equal "reply.rejected", transmissions.last.fetch("type")
      assert_equal "not_found", transmissions.last.fetch("error")
    end
  end

  test "nonmember admins cannot reply and removed members lose reply access" do
    parent = @book_club.club_messages.create!(user: @owner, body: "A question")
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id
    assert_no_difference "ClubMessage.count" do
      perform :post_reply, request_id: "admin-reply", parent_id: parent.id, body: "An answer"
    end
    assert_equal "forbidden", transmissions.last.fetch("error")

    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    assert_no_difference "ClubMessage.count" do
      perform :post_reply, request_id: "former-member", parent_id: parent.id, body: "An answer"
    end
    assert_equal "access.revoked", transmissions.last.fetch("type")
  end

  test "invalid reply bodies return errors without saving or broadcasting" do
    parent = @book_club.club_messages.create!(user: @owner, body: "A question")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    assert_no_difference "ClubMessage.count" do
      assert_no_broadcasts @book_club do
        perform :post_reply, request_id: "blank-reply", parent_id: parent.id, body: " "
      end
    end
    assert_equal "reply.rejected", transmissions.last.fetch("type")
    assert_includes transmissions.last.fetch("errors").fetch("body"), "can't be blank"
  end

  test "posts and replies share the same 20 attempt limit" do
    freeze_time do
      parent = @book_club.club_messages.create!(user: @owner, body: "A question")
      stub_connection current_user: @member
      subscribe book_club_id: @book_club.id
      10.times do |number|
        perform :post_message, request_id: "post-#{number}", body: "A thought"
        perform :post_reply, request_id: "reply-#{number}", parent_id: parent.id, body: "An answer"
      end
      assert_no_difference "ClubMessage.count" do
        perform :post_reply, request_id: "over-limit", parent_id: parent.id, body: "Another answer"
      end
      assert_equal "rate_limited", transmissions.last.fetch("error")
    end
  end

  test "club owner can subscribe to the club discussion" do
    stub_connection current_user: @owner

    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_has_stream_for @book_club
  end

  test "club member can subscribe to the club discussion" do
    stub_connection current_user: @member

    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_has_stream_for @book_club
  end

  test "nonmember admin can subscribe to the club discussion" do
    stub_connection current_user: @admin

    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_has_stream_for @book_club
  end

  test "ordinary nonmember cannot subscribe" do
    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    stub_connection current_user: @member

    subscribe book_club_id: @book_club.id

    assert subscription.rejected?
    assert_no_streams
  end

  test "membership in another club does not grant discussion access" do
    other_club = BookClub.create!(name: "Another circle")
    stub_connection current_user: @member

    subscribe book_club_id: other_club.id

    assert subscription.rejected?
    assert_no_streams
  end

  test "guest cannot subscribe" do
    stub_connection current_user: nil

    subscribe book_club_id: @book_club.id

    assert subscription.rejected?
    assert_no_streams
  end

  test "members save through the channel and receive the saved payload and total" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_difference "ClubMessage.count", 1 do
      perform :post_message, request_id: "post-1", body: "A new thought"
    end

    result = transmissions.last
    message = ClubMessage.find(result.fetch("message").fetch("id"))
    assert_equal "post.saved", result.fetch("type")
    assert_equal "post-1", result.fetch("request_id")
    assert_equal @member, message.user
    assert_equal @book_club, message.book_club
    assert_equal "A new thought", message.body
    assert_equal message.discussion_payload.as_json, result.fetch("message")
    assert_equal 1, result.fetch("total_posts")
  end

  test "posting ignores spoofed author club id and timestamps" do
    other_club = BookClub.create!(name: "Another circle")
    post = @book_club.club_messages.create!(user: @owner, body: "A discussion question")
    @book_club.club_messages.create!(parent: post, user: @owner, body: "A separate answer")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    perform :post_message, request_id: "post-1", body: "My thought", user_id: @admin.id,
      book_club_id: other_club.id, id: 1, parent_id: post.id, created_at: "2000-01-01T00:00:00Z"

    message = ClubMessage.find(transmissions.last.fetch("message").fetch("id"))
    assert_equal @member, message.user
    assert_equal @book_club, message.book_club
    assert_nil message.parent_id
    assert_equal 2, transmissions.last.fetch("total_posts")
    assert_not_equal 2000, message.created_at.year
    assert_empty other_club.club_messages
  end

  test "invalid and missing bodies return errors without saving or broadcasting" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    bodies = [ nil, "", " \n\t ", "a" * 1_001, { "unexpected" => "object" } ]

    bodies.each do |body|
      assert_no_broadcasts @book_club do
        assert_no_difference "ClubMessage.count" do
          perform :post_message, request_id: "invalid-post", body: body
        end
      end

      result = transmissions.last
      assert_equal "post.rejected", result.fetch("type")
      assert_equal "invalid-post", result.fetch("request_id")
      assert result.fetch("errors").fetch("body").any?
    end
  end

  test "nonmember admin cannot post but keeps read access" do
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id

    assert_no_difference "ClubMessage.count" do
      perform :post_message, request_id: "admin-post", body: "Not allowed"
    end

    assert_equal({ "type" => "post.rejected", "request_id" => "admin-post", "error" => "forbidden" }, transmissions.last)
    assert_has_stream_for @book_club
  end

  test "removal after subscribing prevents posting and revokes access" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    assert_no_difference "ClubMessage.count" do
      perform :post_message, request_id: "former-member-post", body: "Not allowed"
    end

    assert_equal({ "type" => "access.revoked" }, transmissions.last)
    assert_no_streams
  end

  test "an admin demoted after subscribing cannot post using a stale user record" do
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id
    User.find(@admin.id).update!(role: "user")

    assert_no_difference "ClubMessage.count" do
      perform :post_message, request_id: "demoted-admin", body: "Not allowed"
    end

    assert_equal({ "type" => "access.revoked" }, transmissions.last)
    assert_no_streams
  end

  test "a deleted club cannot receive posts" do
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id
    @book_club.destroy!

    assert_no_difference "ClubMessage.count" do
      perform :post_message, request_id: "deleted-club", body: "Not allowed"
    end

    assert_equal({ "type" => "access.revoked" }, transmissions.last)
  end

  test "missing or oversized request ids cannot create a post" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    [ nil, "", "a" * 65 ].each do |request_id|
      assert_no_difference "ClubMessage.count" do
        perform :post_message, request_id: request_id, body: "Not saved"
      end
    end
  end

  test "the first 20 posts are saved and the 21st is rejected without broadcasting" do
    freeze_time
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_difference "ClubMessage.count", 20 do
      20.times do |number|
        perform :post_message, request_id: "post-#{number}", body: "Thought #{number}"
        assert_equal "post.saved", transmissions.last.fetch("type")
      end
    end

    assert_no_broadcasts @book_club do
      assert_no_difference "ClubMessage.count" do
        perform :post_message, request_id: "over-limit", body: "Not saved"
      end
    end

    assert_equal({ "type" => "post.rejected", "request_id" => "over-limit", "error" => "rate_limited" }, transmissions.last)
    assert_has_stream_for @book_club
  end

  test "the same user shares the posting limit across clubs and subscriptions" do
    freeze_time
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    20.times do |number|
      perform :post_message, request_id: "post-#{number}", body: "A thought"
    end

    other_club = BookClub.create!(name: "Another circle")
    other_club.book_club_memberships.create!(user: @member, role: "member")
    unsubscribe
    subscribe book_club_id: other_club.id

    assert_no_difference "ClubMessage.count" do
      perform :post_message, request_id: "another-club", body: "Not saved"
    end

    assert_equal "rate_limited", transmissions.last.fetch("error")
    assert_empty other_club.club_messages
  end

  test "one member reaching the posting limit does not block another member" do
    freeze_time
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    20.times do |number|
      perform :post_message, request_id: "post-#{number}", body: "A thought"
    end
    unsubscribe
    stub_connection current_user: @owner
    subscribe book_club_id: @book_club.id

    assert_difference "ClubMessage.count", 1 do
      perform :post_message, request_id: "owner-post", body: "Another member's thought"
    end

    assert_equal "post.saved", transmissions.last.fetch("type")
  end

  test "invalid posts count toward the posting limit" do
    freeze_time
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_no_difference "ClubMessage.count" do
      20.times do |number|
        perform :post_message, request_id: "invalid-#{number}", body: ""
        assert transmissions.last.fetch("errors").fetch("body").any?
      end
      perform :post_message, request_id: "over-limit", body: "Valid but over the limit"
    end

    assert_equal "rate_limited", transmissions.last.fetch("error")
  end

  test "a new minute allows posting again" do
    travel_to Time.current.beginning_of_minute + 10.seconds do
      stub_connection current_user: @member
      subscribe book_club_id: @book_club.id
      20.times do |number|
        perform :post_message, request_id: "post-#{number}", body: "A thought"
      end
      perform :post_message, request_id: "over-limit", body: "Not saved"
      assert_equal "rate_limited", transmissions.last.fetch("error")

      travel 1.minute

      assert_difference "ClubMessage.count", 1 do
        perform :post_message, request_id: "next-minute", body: "Allowed again"
      end
      assert_equal "post.saved", transmissions.last.fetch("type")
    end
  end

  test "missing club is rejected" do
    stub_connection current_user: @admin

    subscribe book_club_id: nil

    assert subscription.rejected?
    assert_no_streams
  end
end
