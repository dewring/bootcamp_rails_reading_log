require "test_helper"
require_relative "../support/discussion_test_connection"

class ClubDiscussionPresenceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @book_club = BookClub.create!(name: "Live presence circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
    @server = ActionCable.server
    @connections = []
    @namespace = "booknook:test:presence_delivery:#{Process.pid}:#{SecureRandom.hex(8)}"
    @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    @key = "#{@namespace}:#{@book_club.id}"
    allow(ClubPresence).to receive(:new).and_wrap_original do |original, book_club, redis:|
      original.call(book_club, redis: redis, namespace: @namespace)
    end
  end

  teardown do
    @connections.each { |connection| connection.subscriptions.unsubscribe_from_all }
    executor = @server.worker_pool.executor
    executor.shutdown
    assert executor.wait_for_termination(5)
    @server.restart
    @book_club.destroy!
    @redis.del(@key)
  ensure
    @redis&.close
  end

  test "real streams keep a member present until their last tab closes" do
    first_tab = subscribe_to_presence(@member)
    second_tab = subscribe_to_presence(@member)
    observer = subscribe_to_presence(@owner)
    expected_ids = [ @owner.id, @member.id ].sort
    snapshot = next_snapshot_with_ids(first_tab, expected_ids)
    assert_equal "presence.snapshot", snapshot.fetch("type")
    assert_equal expected_ids, snapshot.fetch("members").map { |member| member.fetch("id") }
    assert_not snapshot.key?("member_ids")

    first_tab.subscriptions.unsubscribe_from_all
    next_snapshot_with_ids(observer, expected_ids)
    assert_equal 2, @redis.zcard(@key)

    second_tab.subscriptions.unsubscribe_from_all
    next_snapshot_with_ids(observer, [ @owner.id ])
    assert_equal 1, @redis.zcard(@key)
  end

  test "membership loss revokes real delivery and updates the observers roster" do
    departed = subscribe_to_presence(@member)
    observer = subscribe_to_presence(@owner)
    next_snapshot_with_ids(departed, [ @owner.id, @member.id ].sort)

    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    revoked = next_event(departed, "access.revoked")
    assert_equal({ "type" => "access.revoked" }, revoked)
    next_snapshot_with_ids(observer, [ @owner.id ])
    assert_equal 1, @redis.zcard(@key)
  end

  test "real streams deliver typing with server derived identity and no message or notification records" do
    sender = subscribe_to_presence(@member)
    observer = subscribe_to_presence(@owner)
    identifier = { channel: "ClubDiscussionChannel", book_club_id: @book_club.id }.to_json

    assert_no_difference [ "ClubMessage.count", "Noticed::Event.count", "Noticed::Notification.count" ] do
      sender.subscriptions.perform_action(
        "identifier" => identifier,
        "data" => { action: "typing", user_id: @owner.id, body: "Private draft", connection_token: "spoofed" }.to_json
      )
    end

    event = next_event(observer, "typing.started")
    assert_equal({ "id" => @member.id, "nickname" => @member.nickname }, event.fetch("member"))
    assert_match(/\A[0-9a-f]{32}\z/, event.fetch("connection_token"))
    assert_not event.key?("body")
    assert_not event.key?("user_id")
  end

  private

  def subscribe_to_presence(user)
    connection = DiscussionTestConnection.new(server: @server, user: user, include_presence: true)
    @connections.push(connection)
    identifier = { channel: "ClubDiscussionChannel", book_club_id: @book_club.id }.to_json
    connection.subscriptions.add("identifier" => identifier)
    # A direct initial snapshot and stream confirmation may arrive in either order.
    confirmation = Timeout.timeout(5) do
      loop do
        frame = connection.next_message_data
        break frame if frame["type"] == "confirm_subscription"
      end
    end
    assert_equal identifier, confirmation.fetch("identifier")
    connection
  end

  def next_snapshot_with_ids(connection, expected_ids)
    Timeout.timeout(5) do
      loop do
        snapshot = next_event(connection, "presence.snapshot")
        member_ids = snapshot.fetch("members").map { |member| member.fetch("id") }
        return snapshot if member_ids == expected_ids
      end
    end
  end

  def next_event(connection, type)
    Timeout.timeout(5) do
      loop do
        event = connection.next_message_data["message"]
        return event if event && event["type"] == type
      end
    end
  end
end
