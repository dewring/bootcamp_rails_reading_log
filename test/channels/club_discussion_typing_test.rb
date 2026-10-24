require "test_helper"

class ClubDiscussionTypingTest < ActionCable::Channel::TestCase
  tests ClubDiscussionChannel

  setup do
    @book_club = BookClub.create!(name: "Typing circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
    presence = instance_double(ClubPresence, renew_connection: [], active_member_ids: [], remove_connection: [])
    allow(ClubPresence).to receive(:new).and_return(presence)
    @stream_callbacks = []
    allow_any_instance_of(ClubDiscussionChannel).to receive(:stream_for).and_wrap_original do |original, *arguments, **keywords, &callback|
      @stream_callbacks.push(callback)
      original.call(*arguments, **keywords, &callback)
    end
    allow(Process).to receive(:clock_gettime).and_call_original
    set_monotonic_time(100.0)
  end

  test "typing broadcasts server identity token and time without saving messages or notifications" do
    freeze_time do
      stub_connection current_user: @member
      subscribe book_club_id: @book_club.id

      assert_no_difference [ "ClubMessage.count", "Noticed::Event.count", "Noticed::Notification.count" ] do
        perform :typing, user_id: @owner.id, connection_token: "spoofed", generated_at: "2000-01-01T00:00:00Z",
          book_club_id: 0, nickname: "Spoofed", body: "A private draft"
      end

      event = typing_events.last
      assert_equal [ "connection_token", "generated_at", "type", "user_id" ], event.keys.sort
      assert_equal @member.id, event.fetch("user_id")
      assert_match(/\A[0-9a-f]{32}\z/, event.fetch("connection_token"))
      assert_equal Time.current.iso8601(6), event.fetch("generated_at")
      @stream_callbacks.last.call(event)
      assert_equal({ "id" => @member.id, "nickname" => @member.nickname }, transmissions.last.fetch("member"))
      assert_not transmissions.last.key?("user_id")
    end
  end

  test "typing is ignored before one second and accepted at exactly one second" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    perform :typing
    set_monotonic_time(100.999)
    assert_no_broadcasts(@book_club) { perform :typing }

    set_monotonic_time(101.0)
    assert_broadcasts(@book_club, 1) { perform :typing }
    assert_equal 2, typing_events.size
  end

  test "frequent ignored typing does not postpone the next allowed event" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    perform :typing
    set_monotonic_time(100.9)
    10.times { perform :typing }
    set_monotonic_time(101.0)

    perform :typing

    assert_equal 2, typing_events.size
  end

  test "separate tabs have independent typing limits and different tokens" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    perform :typing
    first_event = typing_events.last
    subscribe book_club_id: @book_club.id

    perform :typing

    assert_equal 2, typing_events.size
    assert_not_equal first_event.fetch("connection_token"), typing_events.last.fetch("connection_token")
  end

  test "club owners can send typing events" do
    stub_connection current_user: @owner
    subscribe book_club_id: @book_club.id

    perform :typing

    assert_equal @owner.id, typing_events.last.fetch("user_id")
  end

  test "nonmember admins retain read access but cannot send typing" do
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id
    initial_transmissions = transmissions.dup

    assert_no_broadcasts(@book_club) { perform :typing }

    assert_equal initial_transmissions, transmissions
    assert_has_stream_for @book_club
  end

  test "membership loss revokes typing access before checking the frequency limit" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    perform :typing
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    perform :typing

    assert_no_streams
    assert_equal "access.revoked", transmissions.last.fetch("type")
    assert_equal 1, typing_events.size
  end

  test "typing from a sender who left is dropped before delivery to another member" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    perform :typing
    event = typing_events.last
    stub_connection current_user: @owner
    subscribe book_club_id: @book_club.id
    initial_transmissions = transmissions.dup
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    @stream_callbacks.last.call(event)

    assert_equal initial_transmissions, transmissions
  end

  test "a departed recipient receives revocation instead of a queued typing event" do
    stub_connection current_user: @owner
    subscribe book_club_id: @book_club.id
    perform :typing
    event = typing_events.last
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    @book_club.book_club_memberships.find_by!(user: @member).destroy!

    @stream_callbacks.last.call(event)

    assert_equal "access.revoked", transmissions.last.fetch("type")
    assert_no_streams
  end

  test "typing events are delivered before three seconds and dropped at exactly three seconds" do
    freeze_time do
      stub_connection current_user: @member
      subscribe book_club_id: @book_club.id
      perform :typing
      event = typing_events.last
      travel 2.seconds
      @stream_callbacks.last.call(event)
      assert_equal "typing.started", transmissions.last.fetch("type")
      initial_transmissions = transmissions.dup
      travel 1.second

      @stream_callbacks.last.call(event)

      assert_equal initial_transmissions, transmissions
    end
  end

  test "typing broadcasts only to the subscribed club" do
    other_club = BookClub.create!(name: "Another typing circle")
    other_club.book_club_memberships.create!(user: @owner, role: "owner")
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_no_broadcasts(other_club) { perform :typing, book_club_id: other_club.id }

    assert_equal 1, typing_events.size
  end

  test "a nonmember admin can receive a current members typing event" do
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id
    perform :typing
    event = typing_events.last
    stub_connection current_user: @admin
    subscribe book_club_id: @book_club.id

    @stream_callbacks.last.call(event)

    assert_equal "typing.started", transmissions.last.fetch("type")
    assert_equal @member.id, transmissions.last.fetch("member").fetch("id")
  end

  test "typing does not access presence Redis after a presence-only outage" do
    pool = Rails.configuration.x.club_presence.redis_pool
    allow(pool).to receive(:with).and_raise(Redis::CannotConnectError)
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    assert_broadcasts(@book_club, 1) { perform :typing }

    assert_equal 1, typing_events.size
    assert_has_stream_for @book_club
  end

  private

  def typing_events
    broadcasts(ClubDiscussionChannel.broadcasting_for(@book_club)).map do |event|
      JSON.parse(event)
    end.select { |event| event.fetch("type") == "typing.started" }
  end

  def set_monotonic_time(time)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(time)
  end
end
