require "test_helper"
require_relative "../support/discussion_test_connection"

class ClubDiscussionDeliveryTest < ActiveSupport::TestCase
  # Cable workers use separate database connections and must see committed changes.
  self.use_transactional_tests = false

  setup do
    presence = instance_double(ClubPresence, renew_connection: [], active_member_ids: [], remove_connection: [])
    allow(ClubPresence).to receive(:new).and_return(presence)
    @book_club = BookClub.create!(name: "Discussion circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")

    config = ActionCable::Server::Configuration.new
    config.logger = Rails.logger
    config.cable = { "adapter" => "inline" }
    config.worker_pool_size = 1
    @server = ActionCable::Server::Base.new(config: config)
    @stream = ClubDiscussionChannel.broadcasting_for(@book_club)
  end

  teardown do
    @connection&.subscriptions&.unsubscribe_from_all
    if @server
      executor = @server.worker_pool.executor
      executor.shutdown
      assert executor.wait_for_termination(5)
      @server.restart
      @server.event_loop.stop
    end
    @book_club&.destroy! if @book_club&.persisted?
  end

  test "member receives a broadcast discussion event" do
    subscribe_to_discussion(@member)
    event = { "type" => "message.created", "message" => { "body" => "A new thought" } }

    @server.broadcast(@stream, event)

    assert_equal event, @connection.next_message_data.fetch("message")
  end

  test "removed member receives revocation instead of private content" do
    subscribe_to_discussion(@member)
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    assert_access_revoked
  end

  test "nonmember admin receives a broadcast discussion event" do
    subscribe_to_discussion(@admin)
    event = { "type" => "message.created", "message" => { "body" => "A new thought" } }

    @server.broadcast(@stream, event)

    assert_equal event, @connection.next_message_data.fetch("message")
  end

  test "admin who loses admin role without membership loses access" do
    subscribe_to_discussion(@admin)
    User.find(@admin.id).update!(role: "user")

    assert_access_revoked
  end

  test "deleted club revokes access even for an admin" do
    subscribe_to_discussion(@admin)
    @book_club.destroy!

    assert_access_revoked
  end

  test "deleted user loses discussion access" do
    subscribe_to_discussion(@member)
    User.find(@member.id).destroy!

    assert_access_revoked
  end

  private

  def subscribe_to_discussion(user)
    @connection = DiscussionTestConnection.new(server: @server, user: user)
    identifier = { channel: "ClubDiscussionChannel", book_club_id: @book_club.id }.to_json

    @connection.subscriptions.add("identifier" => identifier)

    assert_equal "confirm_subscription", @connection.next_message_data.fetch("type")
  end

  def assert_access_revoked
    event = { "type" => "message.created", "message" => { "body" => "Private thought" } }
    @server.broadcast(@stream, event)

    assert_equal({ "type" => "access.revoked" }, @connection.next_message_data.fetch("message"))

    # Finish any queued deliveries before checking that no private content was sent.
    @server.broadcast(@stream, event)
    @server.worker_pool.executor.shutdown
    assert @server.worker_pool.executor.wait_for_termination(5)
    assert @connection.received_message_data.empty?
  end
end
