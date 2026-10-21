require "test_helper"
require_relative "../support/discussion_test_connection"

class ClubDiscussionPostingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Rack::Attack.reset!
    @book_club = BookClub.create!(name: "Cable posting circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
    @server = ActionCable.server
    @connections = []
    @identifier = { channel: "ClubDiscussionChannel", book_club_id: @book_club.id }.to_json
  end

  teardown do
    @connections.each { |connection| connection.subscriptions.unsubscribe_from_all }
    executor = @server.worker_pool.executor
    executor.shutdown
    assert executor.wait_for_termination(5)
    @server.restart
    @book_club.destroy!
    Rack::Attack.reset!
  end

  test "editing a post or reply acknowledges its author and broadcasts the committed update to both members" do
    message = @book_club.club_messages.create!(user: @member, body: "Original thought")
    reply = @book_club.club_messages.create!(parent: message, user: @member, body: "Original answer")
    sender = subscribe_to_discussion(@member)
    reader = subscribe_to_discussion(@owner)
    changes = [ { message: message, type: "message.updated" }, { message: reply, type: "reply.updated" } ]

    changes.each do |change|
      target = change.fetch(:message)
      request_id = "edit-#{target.id}"
      sender.subscriptions.perform_action(
        "identifier" => @identifier,
        "data" => { action: "update_message", request_id: request_id, message_id: target.id, body: "Revised content" }.to_json
      )

      events = [ sender.next_message_data.fetch("message"), sender.next_message_data.fetch("message") ]
      saved = events.find { |event| event.fetch("type") == "edit.saved" }
      updated = events.find { |event| event.fetch("type") == change.fetch(:type) }
      assert_equal "Revised content", target.reload.body
      assert_equal request_id, saved.fetch("request_id")
      assert_equal target.discussion_payload.as_json, saved.fetch("message")
      assert_equal saved.fetch("message"), updated.fetch("message")
      assert_equal updated, reader.next_message_data.fetch("message")
      assert_equal @member, target.user
    end
  end

  test "posting through Cable acknowledges the sender and broadcasts the committed post to both members" do
    sender = subscribe_to_discussion(@member)
    reader = subscribe_to_discussion(@owner)

    assert_difference "ClubMessage.count", 1 do
      sender.subscriptions.perform_action(
        "identifier" => @identifier,
        "data" => { action: "post_message", request_id: "post-1", body: "A Cable thought" }.to_json
      )
    end

    # Direct acknowledgements and stream broadcasts may arrive in either order.
    sender_events = [ sender.next_message_data.fetch("message"), sender.next_message_data.fetch("message") ]
    saved = sender_events.find { |event| event.fetch("type") == "post.saved" }
    created = sender_events.find { |event| event.fetch("type") == "message.created" }
    message = @book_club.club_messages.last

    assert_equal "post-1", saved.fetch("request_id")
    assert_equal message.discussion_payload.as_json, saved.fetch("message")
    assert_equal saved.fetch("message"), created.fetch("message")
    assert_equal 1, saved.fetch("total_posts")
    assert_equal created, reader.next_message_data.fetch("message")
    assert_equal @member, message.user
  end

  test "reply submission acknowledges the sender and broadcasts the committed reply to both members" do
    parent = @book_club.club_messages.create!(user: @owner, body: "A question")
    sender = subscribe_to_discussion(@member)
    reader = subscribe_to_discussion(@owner)

    assert_difference "ClubMessage.count", 1 do
      sender.subscriptions.perform_action(
        "identifier" => @identifier,
        "data" => { action: "post_reply", request_id: "reply-1", parent_id: parent.id, body: "An answer" }.to_json
      )
    end

    events = [ sender.next_message_data.fetch("message"), sender.next_message_data.fetch("message") ]
    saved = events.find { |event| event.fetch("type") == "reply.saved" }
    created = events.find { |event| event.fetch("type") == "reply.created" }
    assert_equal "reply-1", saved.fetch("request_id")
    assert_equal parent.replies.last.discussion_payload.as_json, saved.fetch("message")
    assert_equal saved.fetch("message"), created.fetch("message")
    assert_equal 1, created.fetch("total_posts")
    assert_equal created, reader.next_message_data.fetch("message")
  end

  test "validation errors are sent only to the submitting member" do
    sender = subscribe_to_discussion(@member)
    reader = subscribe_to_discussion(@owner)

    assert_no_difference "ClubMessage.count" do
      sender.subscriptions.perform_action(
        "identifier" => @identifier,
        "data" => { action: "post_message", request_id: "invalid-post", body: "" }.to_json
      )
    end

    result = sender.next_message_data.fetch("message")
    assert_equal "post.rejected", result.fetch("type")
    assert_equal "invalid-post", result.fetch("request_id")
    assert_includes result.fetch("errors").fetch("body"), "can't be blank"
    assert reader.received_message_data.empty?
  end

  private

  def subscribe_to_discussion(user)
    connection = DiscussionTestConnection.new(server: @server, user: user)
    @connections.push(connection)
    connection.subscriptions.add("identifier" => @identifier)
    assert_equal "confirm_subscription", connection.next_message_data.fetch("type")
    connection
  end
end
