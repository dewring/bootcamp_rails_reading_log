require "test_helper"

class ClubMessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @book_club = BookClub.create!(name: "Discussion circle")
    @owner = users(:leika)
    @member = users(:jaina)
    @admin = users(:admin)
    @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    @book_club.book_club_memberships.create!(user: @member, role: "member")
    @message = @book_club.club_messages.create!(user: @owner, body: "First thought")
  end

  test "history and posting require sign in" do
    get book_club_club_messages_path(@book_club), as: :json

    assert_response :unauthorized
    assert_not_includes response.body, @message.body

    assert_no_difference "ClubMessage.count" do
      post book_club_club_messages_path(@book_club), params: { club_message: { body: "Guest thought" } }, as: :json
    end
    assert_response :unauthorized
  end

  test "member receives message history with only the public discussion fields" do
    sign_in @member

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ {
      "id" => @message.id,
      "body" => "First thought",
      "author" => { "id" => @owner.id, "nickname" => @owner.nickname },
      "created_at" => @message.created_at.iso8601(6),
      "updated_at" => @message.updated_at.iso8601(6)
    } ], response.parsed_body.fetch("messages")
  end

  test "history returns only the latest 20 messages in descending id order" do
    messages = [ @message ]
    21.times do |number|
      messages.push(@book_club.club_messages.create!(user: @member, body: "Thought #{number}"))
    end
    sign_in @member

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :success
    assert_equal messages.last(20).reverse.map(&:id), response.parsed_body.fetch("messages").map { |message| message.fetch("id") }
  end

  test "nonmember admin can read history without leaking another clubs messages" do
    other_club = BookClub.create!(name: "Another circle")
    other_club.club_messages.create!(user: @owner, body: "Another club's thought")
    sign_in @admin

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :success
    assert_equal [ @message.id ], response.parsed_body.fetch("messages").map { |message| message.fetch("id") }
  end

  test "nonmember cannot read history or post even when they can view the club" do
    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    sign_in @member

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :forbidden
    assert_equal({ "error" => "Forbidden" }, response.parsed_body)
    assert_not_includes response.body, @message.body

    assert_no_difference "ClubMessage.count" do
      post book_club_club_messages_path(@book_club), params: { club_message: { body: "Former member thought" } }, as: :json
    end
    assert_response :forbidden
  end

  test "member can persist a message and receives the same payload in history" do
    sign_in @member

    assert_difference "ClubMessage.count", 1 do
      post book_club_club_messages_path(@book_club), params: { club_message: { body: "A new thought" } }, as: :json
    end

    assert_response :created
    payload = response.parsed_body.fetch("message")
    message = ClubMessage.find(payload.fetch("id"))
    assert_equal @book_club, message.book_club
    assert_equal @member, message.user
    assert_equal "A new thought", message.body
    assert_equal message.discussion_payload.as_json, payload

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :success
    assert_includes response.parsed_body.fetch("messages"), payload
  end

  test "posting ignores spoofed author club id and timestamps" do
    other_club = BookClub.create!(name: "Another circle")
    sign_in @member

    assert_difference "ClubMessage.count", 1 do
      post book_club_club_messages_path(@book_club), params: {
        club_message: {
          body: "My thought",
          user_id: @admin.id,
          book_club_id: other_club.id,
          id: @message.id,
          created_at: "2000-01-01T00:00:00Z"
        }
      }, as: :json
    end

    assert_response :created
    message = ClubMessage.find(response.parsed_body.fetch("message").fetch("id"))
    assert_equal @member, message.user
    assert_equal @book_club, message.book_club
    assert_not_equal @message.id, message.id
    assert_not_equal 2000, message.created_at.year
    assert_equal "First thought", @message.reload.body
  end

  test "invalid bodies return validation errors without persisting" do
    sign_in @member
    bodies = [ "", " \n\t ", "a" * 1_001 ]

    bodies.each do |body|
      assert_no_difference "ClubMessage.count" do
        post book_club_club_messages_path(@book_club), params: { club_message: { body: body } }, as: :json
      end

      assert_response :unprocessable_entity
      assert response.parsed_body.fetch("errors").fetch("body").any?
    end
  end

  test "nonmember admin cannot post" do
    sign_in @admin

    assert_no_difference "ClubMessage.count" do
      post book_club_club_messages_path(@book_club), params: { club_message: { body: "Admin thought" } }, as: :json
    end

    assert_response :forbidden
  end

  test "missing message parameters return bad request without persisting" do
    sign_in @member

    assert_no_difference "ClubMessage.count" do
      post book_club_club_messages_path(@book_club), params: {}, as: :json
    end

    assert_response :bad_request
  end

  test "missing club returns not found" do
    sign_in @member

    get book_club_club_messages_path(book_club_id: 0), as: :json

    assert_response :not_found
  end
end
