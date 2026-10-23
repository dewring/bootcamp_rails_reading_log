require "test_helper"
require_relative "../support/discussion_test_connection"

class ClubDiscussionRevocationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    presence = instance_double(ClubPresence, renew_connection: [], active_member_ids: [], remove_connection: [])
    allow(ClubPresence).to receive(:new).and_return(presence)
    @book_club = BookClub.create!(name: "Discussion circle")
    @member = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    @membership = @book_club.book_club_memberships.create!(user: @member, role: "member")
    # Rails' test adapter records broadcasts and delivers them through real streams.
    @server = ActionCable.server
  end

  teardown do
    @connection&.subscriptions&.unsubscribe_from_all
    executor = @server.worker_pool.executor
    executor.shutdown
    assert executor.wait_for_termination(5)
    @server.restart
    @book_club.destroy!
  end

  test "membership deletion revokes access without a new discussion post" do
    subscribe_to_discussion(@member)

    @membership.destroy!

    assert_equal({ "type" => "access.revoked" }, @connection.next_message_data.fetch("message"))
  end

  test "admin retains access to club messages after leaving book club" do
    admin_membership = @book_club.book_club_memberships.create!(user: @admin, role: "member")
    subscribe_to_discussion(@admin)

    admin_membership.destroy!
    message = @book_club.club_messages.create!(user: @member, body: "Still visible to admins")

    expected = { "type" => "message.created", "message" => message.discussion_payload.as_json, "total_posts" => 1 }
    assert_equal expected, @connection.next_message_data.fetch("message")
  end

  test "remaining member retains access when another member leaves" do
    subscribe_to_discussion(@member)
    other_membership = @book_club.book_club_memberships.create!(user: @admin, role: "member")

    other_membership.destroy!
    message = @book_club.club_messages.create!(user: @member, body: "Still a member")

    expected = { "type" => "message.created", "message" => message.discussion_payload.as_json, "total_posts" => 1 }
    assert_equal expected, @connection.next_message_data.fetch("message")
  end

  private

  def subscribe_to_discussion(user)
    @connection = DiscussionTestConnection.new(server: @server, user: user)
    identifier = { channel: "ClubDiscussionChannel", book_club_id: @book_club.id }.to_json
    @connection.subscriptions.add("identifier" => identifier)

    assert_equal "confirm_subscription", @connection.next_message_data.fetch("type")
  end
end
