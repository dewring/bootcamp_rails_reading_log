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

  test "members have labelled reply forms while nonmember admins can only read replies" do
    sign_in @member
    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "#club_message_#{@message.id} form[data-action='submit->club-replies#postReply']" do
      assert_select "label[for='club_reply_body_#{@message.id}']", text: "Your reply"
      assert_select "textarea#club_reply_body_#{@message.id}[required][maxlength='1000']"
      assert_select "button[type='submit']", text: "Reply"
      assert_select "button[type='button']", text: "Cancel"
    end

    sign_out @member
    sign_in @admin
    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "form[data-action='submit->club-replies#postReply']", count: 0
    assert_select "#club_message_#{@message.id} button[data-action='club-replies#toggle']", count: 1
  end

  test "each post has collapsed reply controls pointing to its own reply history" do
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "#club_message_#{@message.id} [data-controller='club-replies'][data-club-replies-url-value='#{book_club_club_message_replies_path(@book_club, @message)}']" do
      assert_select "button[aria-expanded='false'][data-action='club-replies#toggle']"
      assert_select "[data-club-replies-target='panel'][hidden]"
    end
    assert_select "template[data-club-discussion-target='replyControls']"
  end

  test "members see a labelled discussion form with a 1000 character limit" do
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "section[aria-labelledby='club-discussion-composer-title']" do
      assert_select "form[data-action='submit->club-discussion#postMessage']:not([action])" do
        assert_select "label[for='club_message_body']", text: "Your discussion post"
        assert_select "textarea#club_message_body[required][maxlength='1000']"
        assert_select "button[type='submit'][disabled]", text: "Post"
        assert_select "p[role='status'][data-club-discussion-target='composerStatus']"
      end
    end
    assert_select "p", text: "Posting as #{@member.nickname}"
  end

  test "discussion shows the current book title author pages and compact banner" do
    book = books(:refactoring)
    book.cover_image.attach(io: file_fixture("cover_test.jpg").open, filename: "cover_test.jpg", content_type: "image/jpeg")
    @book_club.update!(current_book: book)
    sign_in @owner

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "article.book-club-current-pick-card--discussion" do
      assert_select ".book-club-current-pick-label", text: "Current Pick"
      assert_select "h2 a[href='#{book_path(book)}']", text: book.title
      assert_select "p", text: "Martin Fowler · 448 pages"
      assert_select ".book-club-current-pick-cover img[alt='Cover of Refactoring']"
      assert_select "a", text: "Change Pick", count: 0
    end
  end

  test "discussion shows an empty current pick banner when no book is selected" do
    sign_in @member

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select ".book-club-current-pick-card--discussion .book-club-current-pick-empty" do
      assert_select "h2", text: "Current pick"
      assert_select "p", text: "No current pick yet."
    end
  end

  test "nonmember admins can read discussion but do not see a posting form" do
    sign_in @admin

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select ".club-discussion-message", count: 1
    assert_select ".club-discussion-composer", count: 0
  end

  test "history requires sign in" do
    get book_club_club_messages_path(@book_club), as: :json

    assert_response :unauthorized
    assert_not_includes response.body, @message.body
  end

  test "discussion has no HTTP posting route" do
    assert_raises ActionController::RoutingError do
      Rails.application.routes.recognize_path(book_club_club_messages_path(@book_club), method: :post)
    end
  end

  test "member receives message history with only the public discussion fields" do
    sign_in @member

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ {
      "id" => @message.id,
      "parent_id" => nil,
      "body" => "First thought",
      "author" => { "id" => @owner.id, "nickname" => @owner.nickname },
      "created_at" => @message.created_at.iso8601(6),
      "updated_at" => @message.updated_at.iso8601(6)
    } ], response.parsed_body.fetch("messages")
  end

  test "history and pagination exclude replies from top-level posts" do
    reply = @book_club.club_messages.create!(parent: @message, user: @member, body: "A separate answer")
    sign_in @member

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :success
    assert_equal [ @message.id ], response.parsed_body.fetch("messages").map { |message| message.fetch("id") }

    get book_club_club_messages_path(@book_club)

    assert_response :success
    assert_select "#club_message_#{@message.id}"
    assert_select "#club_message_#{reply.id}", count: 0
    assert_select "[data-club-discussion-target='paginationSummary']", text: "1 post · Page 1 of 1"
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

  test "nonmember cannot read history even when they can view the club" do
    @book_club.book_club_memberships.find_by!(user: @member).destroy!
    sign_in @member

    get book_club_club_messages_path(@book_club), as: :json

    assert_response :forbidden
    assert_equal({ "error" => "Forbidden" }, response.parsed_body)
    assert_not_includes response.body, @message.body
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
      assert_select "[data-club-discussion-page-value='1'][data-club-discussion-total-posts-value='1']"
      assert_select "[data-action='turbo:before-cache@document->club-discussion#beforeCache']"
      assert_select "[data-club-discussion-target='content'] #club_message_#{@message.id}"
      assert_select "[data-club-discussion-target='messages'] article[data-message-id='#{@message.id}']"
      assert_select "[data-club-discussion-target='emptyState'][hidden]"
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
