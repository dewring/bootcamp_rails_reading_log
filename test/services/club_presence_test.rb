require "test_helper"
require "redis"

class ClubPresenceTest < ActiveSupport::TestCase
  setup do
    @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    @namespace = "booknook:test:club_presence:#{Process.pid}:#{SecureRandom.hex(8)}"
    @book_club = BookClub.create!(name: "Presence circle")
    @other_club = BookClub.create!(name: "Another presence circle")
    @member = users(:leika)
    @other_member = users(:jaina)
    @book_club.book_club_memberships.create!(user: @member, role: "owner")
    @book_club.book_club_memberships.create!(user: @other_member, role: "member")
    @other_club.book_club_memberships.create!(user: @member, role: "owner")
    @presence = ClubPresence.new(@book_club, redis: @redis, namespace: @namespace)
    @other_presence = ClubPresence.new(@other_club, redis: @redis, namespace: @namespace)
    @key = "#{@namespace}:#{@book_club.id}"
    @other_key = "#{@namespace}:#{@other_club.id}"
  end

  teardown do
    # Only these two keys belong to this test, even when workers share Redis.
    @redis.del(@key, @other_key) if @key && @other_key
  ensure
    @redis&.close
  end

  test "two connections count once and removing one keeps the member present" do
    renew(@presence, @member, "first-tab")
    assert_equal [ @member.id ], renew(@presence, @member, "second-tab")

    assert_equal [ @member.id ], @presence.remove_connection(user_id: @member.id, connection_token: "first-tab")
    assert_equal 1, @redis.zcard(@key)
    assert_empty @presence.remove_connection(user_id: @member.id, connection_token: "second-tab")
  end

  test "a connection is present before 45 seconds and expires at exactly 45 seconds" do
    freeze_time do
      renew(@presence, @member, "first-tab")
      travel 44.seconds
      assert_equal [ @member.id ], @presence.active_member_ids

      travel 1.second
      assert_empty @presence.active_member_ids
      assert_equal 0, @redis.zcard(@key)
    end
  end

  test "renewing one tab does not renew another tab belonging to the same member" do
    freeze_time do
      renew(@presence, @member, "first-tab")
      renew(@presence, @member, "second-tab")
      travel 30.seconds
      renew(@presence, @member, "second-tab")
      travel 15.seconds

      assert_equal [ @member.id ], @presence.active_member_ids
      assert_equal [ "#{@member.id}:second-tab" ], @redis.zrange(@key, 0, -1)

      travel 30.seconds
      assert_empty @presence.active_member_ids
    end
  end

  test "renewal prunes expired connections and returns the remaining members" do
    freeze_time do
      renew(@presence, @member, "old-tab")
      travel 45.seconds

      assert_equal [ @other_member.id ], renew(@presence, @other_member, "new-tab")
      assert_equal 1, @redis.zcard(@key)
    end
  end

  test "renewal sets and refreshes a 90 second key TTL" do
    renew(@presence, @member, "first-tab")
    assert_in_delta 90, @redis.ttl(@key), 1
    @redis.expire(@key, 20)

    renew(@presence, @member, "first-tab")

    assert_in_delta 90, @redis.ttl(@key), 1
  end

  test "reading or removing a connection does not extend the idle key TTL" do
    renew(@presence, @member, "first-tab")
    renew(@presence, @member, "second-tab")
    @redis.expire(@key, 20)

    @presence.active_member_ids
    assert_in_delta 20, @redis.ttl(@key), 1
    @presence.remove_connection(user_id: @member.id, connection_token: "first-tab")
    assert_in_delta 20, @redis.ttl(@key), 1
  end

  test "removing an unknown connection preserves other connections" do
    renew(@presence, @member, "first-tab")

    assert_equal [ @member.id ], @presence.remove_connection(user_id: @member.id, connection_token: "unknown-tab")
    assert_equal 1, @redis.zcard(@key)
  end

  test "the same member and token in another club use independent state" do
    renew(@presence, @member, "first-tab")
    renew(@other_presence, @member, "first-tab")
    @presence.remove_connection(user_id: @member.id, connection_token: "first-tab")

    assert_empty @presence.active_member_ids
    assert_equal [ @member.id ], @other_presence.active_member_ids
  end

  test "snapshots exclude users whose membership has been removed" do
    renew(@presence, @member, "first-tab")
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    assert_empty @presence.active_member_ids
  end

  test "a missing key returns an empty roster without creating a key" do
    assert_empty @presence.active_member_ids
    assert_not @redis.exists?(@key)
  end

  test "Redis failures propagate instead of returning an empty roster" do
    allow(@redis).to receive(:multi).and_raise(Redis::CannotConnectError)

    assert_raises(Redis::CannotConnectError) { @presence.active_member_ids }
  end

  private

  def renew(presence, member, token)
    presence.renew_connection(user_id: member.id, connection_token: token)
  end
end
