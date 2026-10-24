require "test_helper"

class ClubDiscussionHeartbeatTest < ActionCable::Channel::TestCase
  tests ClubDiscussionChannel

  setup do
    @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    @namespace = "booknook:test:heartbeat:#{Process.pid}:#{SecureRandom.hex(8)}"
    @book_club = BookClub.create!(name: "Heartbeat circle")
    @member = users(:leika)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @member, role: "owner")
    @key = "#{@namespace}:#{@book_club.id}"
    @owned_keys = [ @key ]
    @stream_callbacks = []
    allow_any_instance_of(ClubDiscussionChannel).to receive(:stream_for).and_wrap_original do |original, *arguments, **keywords, &callback|
      @stream_callbacks.push(callback)
      original.call(*arguments, **keywords, &callback)
    end
    allow(ClubPresence).to receive(:new).and_wrap_original do |original, book_club, redis:|
      original.call(book_club, redis: redis, namespace: @namespace)
    end
    allow(Process).to receive(:clock_gettime).and_call_original
    set_monotonic_time(100.0)
    Rack::Attack.reset!
  end

  teardown do
    @redis.del(*@owned_keys) if @owned_keys.present?
    Rack::Attack.reset!
  ensure
    @redis&.close
  end

  test "a member subscription registers one server generated connection with a 90 second TTL" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id, connection_token: "spoofed-token"

    assert subscription.confirmed?
    entries = @redis.zrange(@key, 0, -1)
    assert_equal 1, entries.size
    assert_match(/\A#{@member.id}:[0-9a-f]{32}\z/, entries.first)
    assert_in_delta 90, @redis.ttl(@key), 1
  end

  test "two subscriptions for the same member receive different connection tokens" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    subscribe book_club_id: @book_club.id

    assert_equal 2, @redis.zcard(@key)
    presence = ClubPresence.new(@book_club, redis: @redis)
    assert_equal [ @member.id ], presence.active_member_ids
  end

  test "presence snapshots include the same attached avatar path used for discussion authors" do
    @member.avatar.attach(io: File.open(file_fixture("cover_test.jpg")), filename: "avatar.jpg", content_type: "image/jpeg")
    stub_connection current_user: @member

    subscribe book_club_id: @book_club.id

    member = transmissions.last.fetch("members").find { |entry| entry.fetch(:id) == @member.id }
    expected_path = Rails.application.routes.url_helpers.rails_blob_path(@member.avatar, only_path: true)
    assert_equal expected_path, member.fetch(:avatar_url)
  end

  test "heartbeat ignores client identity timestamps tokens and club ids" do
    freeze_time do
      stub_connection current_user: @member
      subscribe book_club_id: @book_club.id
      original_entry = @redis.zrange(@key, 0, -1).first
      travel 10.seconds
      set_monotonic_time(110.0)

      perform :heartbeat, user_id: @admin.id, connection_token: "spoofed", timestamp: 0, book_club_id: 0, key: "other-key"

      assert_equal [ original_entry ], @redis.zrange(@key, 0, -1)
      assert_in_delta Time.current.to_f, @redis.zscore(@key, original_entry), 0.001
    end
  end

  test "heartbeat is ignored before five seconds and accepted at exactly five seconds" do
    freeze_time do
      stub_connection current_user: @member
      subscribe book_club_id: @book_club.id
      entry = @redis.zrange(@key, 0, -1).first
      original_score = @redis.zscore(@key, entry)
      travel 4.seconds
      set_monotonic_time(104.0)
      perform :heartbeat
      assert_equal original_score, @redis.zscore(@key, entry)

      travel 1.second
      set_monotonic_time(105.0)
      perform :heartbeat
      assert_in_delta Time.current.to_f, @redis.zscore(@key, entry), 0.001
    end
  end

  test "one subscription reaching the heartbeat limit does not block another subscription" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    10.times { perform :heartbeat }
    subscribe book_club_id: @book_club.id

    assert_equal 2, @redis.zcard(@key)
  end

  test "a nonmember admin can subscribe and heartbeat without appearing online" do
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id
    set_monotonic_time(110.0)
    perform :heartbeat

    assert subscription.confirmed?
    assert_has_stream_for @book_club
    assert_not @redis.exists?(@key)
  end

  test "a nonmember subscription is rejected without registering a connection" do
    stub_connection current_user: users(:jaina)
    subscribe book_club_id: @book_club.id
    assert subscription.rejected?
    assert_not @redis.exists?(@key)
  end

  test "membership loss revokes heartbeat access even before the frequency gate opens" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    perform :heartbeat

    assert_no_streams
    assert_equal "access.revoked", transmissions.last.fetch("type")
  end

  test "presence Redis failure keeps the discussion subscription and posting usable" do
    pool = Rails.configuration.x.club_presence.redis_pool
    allow(pool).to receive(:with).and_raise(Redis::CannotConnectError)
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_has_stream_for @book_club
    assert_equal "presence.unavailable", transmissions.last.fetch("type")
    assert_difference "ClubMessage.count", 1 do
      perform :post_message, request_id: "redis-outage-post", body: "Discussion remains available"
    end
    assert_equal "post.saved", transmissions.last.fetch("type")
  end

  test "heartbeat retries presence after Redis recovers" do
    pool = Rails.configuration.x.club_presence.redis_pool
    allow(pool).to receive(:with).and_raise(Redis::CannotConnectError)
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    allow(pool).to receive(:with).and_call_original
    set_monotonic_time(105.0)

    perform :heartbeat

    assert_equal 1, @redis.zcard(@key)
  end

  test "a Redis pool timeout reports unavailable without rejecting the subscription" do
    pool = Rails.configuration.x.club_presence.redis_pool
    allow(pool).to receive(:with).and_raise(ConnectionPool::TimeoutError)
    stub_connection current_user: @member

    subscribe book_club_id: @book_club.id

    assert subscription.confirmed?
    assert_equal "presence.unavailable", transmissions.last.fetch("type")
  end

  test "joining broadcasts member ids and directly delivers an initial named snapshot" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    event = presence_events.last
    assert_equal [ @member.id ], event.fetch("member_ids")
    assert_equal "presence.snapshot", transmissions.last.fetch("type")
    assert_equal [ { "id" => @member.id, "nickname" => @member.nickname } ], transmissions.last.fetch("members")
    assert_equal event.fetch("generated_at"), transmissions.last.fetch("generated_at")
    assert_not transmissions.last.key?("member_ids")
  end

  test "accepted heartbeats broadcast snapshots and frequent heartbeats do not" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    set_monotonic_time(104.0)
    assert_no_broadcasts(@book_club) { perform :heartbeat }

    set_monotonic_time(105.0)
    assert_broadcasts(@book_club, 1) { perform :heartbeat }
    assert_equal [ @member.id ], presence_events.last.fetch("member_ids")
  end

  test "closing one of two tabs retains one online member and closing the last removes them" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    first_tab = subscription
    subscribe book_club_id: @book_club.id

    assert_equal [ @member.id ], presence_events.last.fetch("member_ids")
    first_tab.unsubscribe_from_channel
    assert_equal 1, @redis.zcard(@key)
    assert_equal [ @member.id ], presence_events.last.fetch("member_ids")

    unsubscribe
    assert_equal 0, @redis.zcard(@key)
    assert_empty presence_events.last.fetch("member_ids")
  end

  test "another members heartbeat removes a connection abandoned for 45 seconds" do
    other_member = users(:jaina)
    @book_club.book_club_memberships.create!(user: other_member, role: "member")
    freeze_time do
      stub_connection current_user: @member
      subscribe book_club_id: @book_club.id
      travel 10.seconds
      stub_connection current_user: other_member
      subscribe book_club_id: @book_club.id
      travel 35.seconds
      set_monotonic_time(135.0)

      perform :heartbeat

      assert_equal [ other_member.id ], presence_events.last.fetch("member_ids")
      assert_equal 1, @redis.zcard(@key)
    end
  end

  test "a nonmember admin receives the roster without being included" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id

    assert_equal [ @member.id ], transmissions.last.fetch("members").map { |member| member.fetch("id") }
    assert_equal 1, @redis.zcard(@key)
  end

  test "membership is rechecked before a queued snapshot reaches an authorized admin" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    event = presence_events.last
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    @stream_callbacks.last.call(event)

    assert_equal "presence.snapshot", transmissions.last.fetch("type")
    assert_empty transmissions.last.fetch("members")
  end

  test "delivery revokes a departed recipients access and removes their connection" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    event = presence_events.last
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    @stream_callbacks.last.call(event)

    assert_no_streams
    assert_equal "access.revoked", transmissions.last.fetch("type")
    assert_equal 0, @redis.zcard(@key)
    assert_empty presence_events.last.fetch("member_ids")
    initial_transmissions = transmissions.dup
    @stream_callbacks.last.call(event)
    assert_equal initial_transmissions, transmissions
  end

  test "access revocation followed by unsubscribe removes the connection only once" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    perform :heartbeat

    assert_no_broadcasts(@book_club) { unsubscribe }
    assert_equal 0, @redis.zcard(@key)
  end

  test "snapshots and connection removal remain isolated between clubs" do
    other_club = BookClub.create!(name: "Isolated presence circle")
    other_club.book_club_memberships.create!(user: @member, role: "owner")
    other_key = "#{@namespace}:#{other_club.id}"
    @owned_keys.push(other_key)
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    first_club_tab = subscription
    subscribe book_club_id: other_club.id

    assert_no_broadcasts(other_club) { first_club_tab.unsubscribe_from_channel }
    assert_equal 1, @redis.zcard(other_key)
    assert_equal 0, @redis.zcard(@key)
    assert_equal [ @member.id ], transmissions.last.fetch("members").map { |member| member.fetch("id") }
  end

  test "snapshot delivery excludes identities belonging only to another club" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    event = presence_events.last.merge("member_ids" => [ @member.id, users(:jaina).id ])

    @stream_callbacks.last.call(event)

    assert_equal [ @member.id ], transmissions.last.fetch("members").map { |member| member.fetch("id") }
  end

  test "Redis cleanup failure broadcasts unavailable and still finishes unsubscribing" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    pool = Rails.configuration.x.club_presence.redis_pool
    allow(pool).to receive(:with).and_raise(Redis::CannotConnectError)

    assert_broadcast_on(@book_club, { type: "presence.unavailable" }) { unsubscribe }

    assert_no_streams
    initial_transmissions = transmissions.dup
    @stream_callbacks.last.call(presence_events.last)
    assert_equal initial_transmissions, transmissions
  end

  private

  def presence_events
    broadcasts(ClubDiscussionChannel.broadcasting_for(@book_club)).map do |event|
      JSON.parse(event)
    end.select { |event| event.fetch("type") == "presence.snapshot" }
  end

  def set_monotonic_time(time)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(time)
  end
end
