require "test_helper"

class DiscussionReactionPanelsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @reader = users(:leika)
    @other = users(:jaina)
    @club = BookClub.create!(name: "Private reaction panels")
    @club.book_club_memberships.create!(user: @reader, role: "member")
    @club.book_club_memberships.create!(user: @other, role: "member")
    @post = @club.club_messages.create!(user: @other, body: "Shared post")
    @reply = @club.club_messages.create!(parent: @post, user: @reader, body: "Shared reply")
    @post.reactions.create!(user: @reader, kind: "like")
    @post.reactions.create!(user: @other, kind: "wow")
    @reply.reactions.create!(user: @reader, kind: "love")
    @reply.reactions.create!(user: @other, kind: "laugh")
    sign_in @reader
  end

  test "initial HTML renders the viewers post panel without loading another frame" do
    get book_club_club_messages_path(@club)

    assert_response :success
    assert_select "#club_message_#{@post.id} turbo-frame#reaction_panel_club_message_#{@post.id}:not([src])" do
      assert_select "button[aria-pressed='true']", text: "👍 1", count: 1
      assert_select "[data-reaction-kind='wow']", text: "😮 Wow: 1"
      assert_select "form[action='#{book_club_club_message_reaction_path(@club, @post)}']", count: 10
    end
    assert_select "#reaction_panel_club_message_#{@reply.id}", count: 0
  end

  test "history keeps shared message payloads identical while panels contain only the viewers selection" do
    get book_club_club_messages_path(@club), as: :json

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal [ @post.discussion_payload.as_json ], response.parsed_body.fetch("messages")
    panels = response.parsed_body.fetch("reaction_panels")
    assert_equal [ @post.id.to_s ], panels.keys
    panel = Nokogiri::HTML.fragment(panels.fetch(@post.id.to_s))
    assert_equal [ "👍 1" ], panel.css("button[aria-pressed='true']").map { |button| button.text.squish }
    shared_payload = response.parsed_body.fetch("messages")

    sign_out @reader
    sign_in @other
    get book_club_club_messages_path(@club), as: :json

    assert_equal shared_payload, response.parsed_body.fetch("messages")
    other_panel = Nokogiri::HTML.fragment(response.parsed_body.fetch("reaction_panels").fetch(@post.id.to_s))
    assert_equal [ "😮 1" ], other_panel.css("button[aria-pressed='true']").map { |button| button.text.squish }
  end

  test "reply history batches private panels separately from shared reply payloads" do
    get book_club_club_message_replies_path(@club, @post), as: :json

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal [ @reply.discussion_payload.as_json ], response.parsed_body.fetch("replies")
    panels = response.parsed_body.fetch("reaction_panels")
    assert_equal [ @reply.id.to_s ], panels.keys
    panel = Nokogiri::HTML.fragment(panels.fetch(@reply.id.to_s))
    assert_equal [ "❤️ 1" ], panel.css("button[aria-pressed='true']").map { |button| button.text.squish }
    assert_equal "😂 Laugh: 1", panel.at_css("[data-reaction-kind='laugh']").text
  end

  test "deleted parents have no private panel while retained replies keep their own panels" do
    @post.remove_from_discussion!

    get book_club_club_messages_path(@club), as: :json
    assert_response :success
    assert_empty response.parsed_body.fetch("reaction_panels")

    get book_club_club_messages_path(@club)
    assert_response :success
    assert_select "#club_message_#{@post.id} .reaction-panel", count: 0

    get book_club_club_message_replies_path(@club, @post), as: :json
    assert_response :success
    assert_equal [ @reply.id.to_s ], response.parsed_body.fetch("reaction_panels").keys
    assert @reply.reactions.exists?(user: @reader)
  end

  test "an authorized nonmember admin gets controls while an invited member only gets totals" do
    sign_out @reader
    sign_in users(:admin)
    get book_club_club_messages_path(@club)
    assert_response :success
    assert_select "#reaction_panel_club_message_#{@post.id} button[aria-pressed='false']", count: 5

    sign_out users(:admin)
    @reader.update!(account_status: "invited")
    sign_in @reader
    get book_club_club_messages_path(@club)
    assert_response :success
    assert_select "#reaction_panel_club_message_#{@post.id} [data-reaction-kind='like']", text: "👍 Like: 0"
    assert_select "#reaction_panel_club_message_#{@post.id} form", count: 0
  end

  test "revoked membership prevents both history endpoints from returning private panels" do
    @club.book_club_memberships.find_by!(user: @reader).destroy!
    [ book_club_club_messages_path(@club), book_club_club_message_replies_path(@club, @post) ].each do |path|
      get path, as: :json

      assert_response :forbidden
      assert_equal({ "error" => "Forbidden" }, response.parsed_body)
      assert_not_includes response.body, "aria-pressed"
    end
  end

  test "post and reply panels use two batched reaction queries regardless of the displayed message count" do
    5.times do |number|
      @club.club_messages.create!(user: @reader, body: "Post #{number}").reactions.create!(user: @reader, kind: "love")
      @club.club_messages.create!(parent: @post, user: @reader, body: "Reply #{number}").reactions.create!(user: @reader, kind: "wow")
    end

    [ book_club_club_messages_path(@club), book_club_club_message_replies_path(@club, @post) ].each do |path|
      queries = reaction_queries { get path, as: :json }

      assert_response :success
      assert_equal 6, response.parsed_body.fetch("reaction_panels").size
      assert_equal 2, queries.length
    end
  end

  test "catalog labels are escaped in private rendered panels" do
    reaction_types(:like).update!(label: "<script>private-label</script>")

    get book_club_club_messages_path(@club), as: :json

    assert_response :success
    panel = Nokogiri::HTML.fragment(response.parsed_body.fetch("reaction_panels").fetch(@post.id.to_s))
    assert_empty panel.css("script")
    assert_includes panel.text, "<script>private-label</script>"
  end

  private

  def reaction_queries
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      sql = payload.fetch(:sql)
      queries.push(sql) if sql.match?(/\ASELECT\b.*\bFROM "club_message_reactions"/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
