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

  test "html history redirects guests to sign in without exposing messages" do
    get book_club_club_messages_path(@book_club)

    assert_redirected_to new_user_session_path
    assert_not_includes response.body, @message.body
  end

  test "html history denies former members without exposing messages" do
    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_redirected_to root_path
    assert_not_includes response.body, @message.body
  end

  test "html history paginates 20 posts newest first and links to older posts" do
    messages = [ @message ]
    21.times do |number|
      message = @book_club.club_messages.create!(user: @member, body: "Thought #{number}")
      messages.push(message)
    end
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    expected_ids = messages.last(20).reverse.map { |message| "club_message_#{message.id}" }
    actual_ids = css_select(".club-discussion-message").map { |element| element["id"] }
    assert_equal expected_ids, actual_ids
    assert_select ".club-discussion-pagination a[href*='page=2']"
    assert_select ".book-club-sidebar-navigation a.is-active[aria-current='page']", text: "Discussion"
    assert_select ".book-club-sidebar-navigation a.is-active", count: 1

    get book_club_club_messages_path(@book_club), params: { page: 2 }

    assert_response :success
    expected_ids = messages.first(2).reverse.map { |message| "club_message_#{message.id}" }
    actual_ids = css_select(".club-discussion-message").map { |element| element["id"] }
    assert_equal expected_ids, actual_ids
  end

  test "html history is readable by nonmember admins and scoped to the requested club" do
    other_club = BookClub.create!(name: "Another circle")
    other_message = other_club.club_messages.create!(user: @owner, body: "Another club's thought")
    sign_in @admin

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "#club_message_#{@message.id}"
    assert_select "#club_message_#{other_message.id}", count: 0
    assert_select ".book-club-member-status", text: "Administrator view"
  end

  test "html history escapes message bodies and author nicknames" do
    @owner.update!(nickname: "<script>author</script>")
    @message.update!(body: "<script>alert('message')</script>")
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select ".club-discussion-message script", count: 0
    assert_select ".club-discussion-message-meta strong", text: @owner.nickname
    assert_select ".club-discussion-message-body", text: @message.body
    assert_includes response.body, "&lt;script&gt;"
  end

  test "html history has an empty state when the club has no messages" do
    @message.destroy!
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select ".club-discussion-empty", text: "No discussion posts yet."
    assert_select ".club-discussion-message", count: 0
  end

  test "discussion page has one main region and a discussion section labelled by its heading" do
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "main", count: 1
    assert_select "main section.book-club-overview-content[aria-labelledby='discussion-title']", count: 1 do
      assert_select "h1#discussion-title", text: "Discussion", count: 1
    end
  end

  test "discussion page includes the required Stimulus settings" do
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "[data-controller='club-discussion'][data-club-discussion-book-club-id-value='#{@book_club.id}']" do
      assert_select "[data-action='turbo:before-cache@document->club-discussion#beforeCache']"
      assert_select "[data-club-discussion-target='content'] #club_message_#{@message.id}"
      assert_select "p[role='status'][data-club-discussion-target='status'][hidden]"
    end
  end

  test "discussion navigation is available to members and admins but hidden from ordinary nonmembers" do
    sign_in @member
    get book_club_path(@book_club)
    assert_select ".book-club-sidebar-navigation a[href='#{book_club_club_messages_path(@book_club)}']", text: "Discussion"

    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    get book_club_path(@book_club)
    assert_select ".book-club-sidebar-navigation a[href='#{book_club_club_messages_path(@book_club)}']", count: 0

    sign_out @member
    sign_in @admin
    get book_club_path(@book_club)
    assert_select ".book-club-sidebar-navigation a[href='#{book_club_club_messages_path(@book_club)}']", text: "Discussion"
  end
end
