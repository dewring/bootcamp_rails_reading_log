require "test_helper"

class ClubDiscussionChannelTest < ActionCable::Channel::TestCase
  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
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
    stub_connection current_user: @member
    subscribe book_club_id: @book_club.id

    perform :post_message, request_id: "post-1", body: "My thought", user_id: @admin.id,
      book_club_id: other_club.id, id: 1, created_at: "2000-01-01T00:00:00Z"

    message = ClubMessage.find(transmissions.last.fetch("message").fetch("id"))
    assert_equal @member, message.user
    assert_equal @book_club, message.book_club
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

  test "missing club is rejected" do
    stub_connection current_user: @admin

    subscribe book_club_id: nil

    assert subscription.rejected?
    assert_no_streams
  end
end
