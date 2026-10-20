require "test_helper"

class ClubMessageRepliesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @book_club = BookClub.create!(name: "Reply circle")
    @member = users(:leika)
    @book_club.book_club_memberships.create!(user: @member, role: "owner")
    @post = @book_club.club_messages.create!(user: @member, body: "A question")
    @reply = @post.replies.create!(book_club: @book_club, user: @member, body: "An answer")
  end

  test "reply history requires sign in" do
    get book_club_club_message_replies_path(@book_club, @post), as: :json

    assert_response :unauthorized
    assert_not_includes response.body, @reply.body
  end

  test "ordinary nonmembers cannot read reply history" do
    sign_in users(:jaina)

    get book_club_club_message_replies_path(@book_club, @post), as: :json

    assert_response :forbidden
    assert_not_includes response.body, @reply.body
  end

  test "nonmember admins can read reply history with the shared payload" do
    sign_in users(:admin)

    get book_club_club_message_replies_path(@book_club, @post), as: :json

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal [ @reply.discussion_payload.as_json ], response.parsed_body.fetch("replies")
  end

  test "reply history returns 20 replies per page in ascending id order" do
    replies = [ @reply ]
    20.times do |number|
      replies.push(@post.replies.create!(book_club: @book_club, user: @member, body: "Answer #{number}"))
    end
    other_post = @book_club.club_messages.create!(user: @member, body: "Another question")
    other_post.replies.create!(book_club: @book_club, user: @member, body: "A separate answer")
    sign_in @member

    get book_club_club_message_replies_path(@book_club, @post), as: :json

    assert_response :success
    assert_equal replies.first(20).map(&:id), response.parsed_body.fetch("replies").map { |reply| reply.fetch("id") }
    assert_equal({ "page" => 1, "next_page" => 2, "last_page" => 2, "total_count" => 21 }, response.parsed_body.fetch("pagination"))

    get book_club_club_message_replies_path(@book_club, @post), params: { page: 2 }, as: :json

    assert_response :success
    assert_equal [ replies.last.id ], response.parsed_body.fetch("replies").map { |reply| reply.fetch("id") }
    assert_nil response.parsed_body.fetch("pagination").fetch("next_page")
  end

  test "reply history rejects parents from another club" do
    other_club = BookClub.create!(name: "Another circle")
    other_post = other_club.club_messages.create!(user: @member, body: "Another question")
    sign_in @member

    get book_club_club_message_replies_path(@book_club, other_post), as: :json

    assert_response :not_found
    assert_not_includes response.body, @reply.body
  end

  test "reply history rejects replies used as parents" do
    sign_in @member

    get book_club_club_message_replies_path(@book_club, @reply), as: :json

    assert_response :not_found
    assert_not_includes response.body, @reply.body
  end
end
