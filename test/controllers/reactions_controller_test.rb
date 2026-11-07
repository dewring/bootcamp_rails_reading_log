require "test_helper"

class ReactionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @reader = users(:leika)
    @other = users(:jaina)
    @book = books(:refactoring)
    @review = reviews(:review1)
    @club = BookClub.create!(name: "HTTP reaction discussion")
    @membership = @club.book_club_memberships.create!(user: @reader, role: "member")
    @message = @club.club_messages.create!(user: @other, body: "A discussion thought")
    @targets = [ @book, @review, @message ]
    @paths = [ book_reaction_path(@book), book_review_reaction_path(@book, @review), book_club_club_message_reaction_path(@club, @message) ]
    @redirects = [ book_path(@book), book_path(@book, anchor: "review_#{@review.id}"), book_club_club_messages_path(@club, anchor: "club_message_#{@message.id}") ]
  end

  test "authorized refresh returns an uncached frame for each concrete target" do
    sign_in @reader
    @targets.zip(@paths).each do |target, path|
      target.reactions.create!(user: @reader, kind: "love")

      get path

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select "turbo-frame#reaction_panel_#{target.model_name.singular}_#{target.id}"
      assert_select "[data-reaction-kind='love']", text: "❤️ Love: 1"
      assert_select "[data-reaction-selection]", text: "Your reaction: Love"
    end
  end

  test "guests see public counts without another readers selection and cannot read discussion reactions" do
    [ @book, @review ].zip(@paths.first(2)).each do |target, path|
      target.reactions.create!(user: @reader, kind: "love")
      get path

      assert_response :success
      assert_select "[data-reaction-kind='love']", text: "❤️ Love: 1"
      assert_select "[data-reaction-selection]", text: "No reaction selected"
    end

    get @paths.last
    assert_redirected_to new_user_session_path
  end

  test "HTML selection and clearing redirect to the corresponding content with see other" do
    sign_in @reader
    @targets.zip(@paths, @redirects).each do |target, path, destination|
      put path, params: { kind: "like" }

      assert_response :see_other
      assert_redirected_to destination
      assert_equal "like", target.reactions.find_by!(user: @reader).kind

      delete path

      assert_response :see_other
      assert_redirected_to destination
      assert_empty target.reactions.reload
    end
  end

  test "Turbo selection switching and clearing replace only the requesting targets panel" do
    sign_in @reader
    @targets.zip(@paths).each do |target, path|
      put path, params: { kind: "like" }, as: :turbo_stream
      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_select "turbo-stream[action='replace'][target='reaction_panel_#{target.model_name.singular}_#{target.id}']", count: 1
      original = target.reactions.find_by!(user: @reader)

      put path, params: { kind: "wow" }, as: :turbo_stream
      assert_response :success
      assert_equal original.id, target.reactions.find_by!(user: @reader).id
      assert_select "[data-reaction-selection]", text: "Your reaction: Wow"

      delete path, as: :turbo_stream
      assert_response :success
      assert_select "[data-reaction-selection]", text: "No reaction selected"
      assert_empty target.reactions.reload
    end
  end

  test "forged user and target attributes cannot change ownership or another readers choice" do
    sign_in @reader
    @targets.zip(@paths).each do |target, path|
      other = target.reactions.create!(user: @other, kind: "like")

      put path, params: { kind: "love", user_id: @other.id, id: other.id, book_id: books(:pragmatic).id }, as: :turbo_stream

      assert_response :success
      assert_equal "like", other.reload.kind
      assert_equal "love", target.reactions.find_by!(user: @reader).kind
      delete path, params: { user_id: @other.id, id: other.id }, as: :turbo_stream
      assert_response :success
      assert other.reload.persisted?
      assert_not target.reactions.exists?(user: @reader)
    end
  end

  test "unknown and missing kinds return HTML and Turbo errors without changing the persisted selection" do
    sign_in @reader
    @targets.zip(@paths).each do |target, path|
      reaction = target.reactions.create!(user: @reader, kind: "like")
      before = reaction.attributes
      [ :html, :turbo_stream ].each do |format|
        [ "unknown", nil ].each do |kind|
          put path, params: { kind: kind }, headers: { "Accept" => format == :html ? "text/html" : "text/vnd.turbo-stream.html" }

          assert_response :unprocessable_entity
          assert_select "ul[role='alert'] li", minimum: 1
          assert_select "[data-reaction-selection]", text: "Your reaction: Like"
          assert_equal before, reaction.reload.attributes
        end
      end
    end
  end

  test "disabled choices remain counted and exact retries preserve timestamps while new selections return 422" do
    sign_in @reader
    originals = @targets.map { |target| target.reactions.create!(user: @reader, kind: "like") }
    reaction_types(:like).update!(enabled: false)

    @targets.zip(@paths, originals).each do |target, path, original|
      before = original.attributes
      put path, params: { kind: "like" }, as: :turbo_stream
      assert_response :success
      assert_equal before, original.reload.attributes
      assert_select "[data-reaction-kind='like']", text: "👍 Like: 1"

      put path, params: { kind: "love" }, as: :turbo_stream
      assert_response :success
      put path, params: { kind: "like" }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_equal "love", original.reload.kind
      delete path, as: :turbo_stream
      assert_response :success
      put path, params: { kind: "like" }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_empty target.reactions.reload
    end
  end

  test "catalog data alone adds a kind to refresh selection and clear responses" do
    ReactionType.create!(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: true)
    sign_in @reader
    @paths.each do |path|
      get path
      assert_response :success
      assert_select "[data-reaction-kind='celebrate']", text: "🎉 Celebrate: 0"
      assert_select ".reaction-choice[aria-label='Celebrate']", text: "🎉"
      put path, params: { kind: "celebrate" }, as: :turbo_stream
      assert_response :success
      assert_select "[data-reaction-kind='celebrate']", text: "🎉 Celebrate: 1"
      assert_select "[data-reaction-selection]", text: "Your reaction: Celebrate"
      assert_select "button[aria-pressed='true']", text: "🎉 1"
      delete path, as: :turbo_stream
      assert_response :success
      assert_select "[data-reaction-kind='celebrate']", text: "🎉 Celebrate: 0"
      assert_select "button[aria-pressed='true']", count: 0
    end
  end

  test "refresh counts only active users and keeps the viewers selection private" do
    sign_in @reader
    @targets.zip(@paths).each do |target, path|
      target.reactions.create!(user: @other, kind: "love")
      get path
      assert_select "[data-reaction-kind='love']", text: "❤️ Love: 1"
      assert_select "[data-reaction-selection]", text: "No reaction selected"
      @other.update!(account_status: "suspended")
      get path
      assert_response :success
      assert_select "[data-reaction-kind='love']", text: "❤️ Love: 0"
      @other.update!(account_status: "active")
    end
  end

  test "guest writes require sign in and never change reactions" do
    @targets.zip(@paths).each do |target, path|
      put path, params: { kind: "like" }
      assert_redirected_to new_user_session_path
      delete path
      assert_redirected_to new_user_session_path
      assert_empty target.reactions.reload
    end
  end

  test "invited readers are forbidden from selecting and clearing on every target" do
    @reader.update!(account_status: "invited")
    sign_in @reader
    @targets.zip(@paths).each do |target, path|
      original = target.reactions.create!(user: @reader, kind: "like")
      put path, params: { kind: "love" }, as: :turbo_stream
      assert_response :forbidden
      delete path, as: :turbo_stream
      assert_response :forbidden
      assert_equal "like", original.reload.kind
    end
  end

  test "suspended readers are sent to sign in without changing reactions" do
    @reader.update!(account_status: "suspended")
    sign_in @reader
    @targets.zip(@paths).each do |target, path|
      put path, params: { kind: "love" }
      assert_redirected_to new_user_session_path
      delete path
      assert_redirected_to new_user_session_path
      assert_empty target.reactions.reload
    end
  end

  test "nonmembers and former members cannot refresh select or clear Discussion reactions" do
    sign_in @other
    get @paths.last
    assert_response :forbidden
    put @paths.last, params: { kind: "like" }
    assert_response :forbidden
    sign_out @other
    sign_in @reader
    original = @message.reactions.create!(user: @reader, kind: "like")
    @membership.destroy!

    get @paths.last
    assert_response :forbidden
    put @paths.last, params: { kind: "love" }
    assert_response :forbidden
    delete @paths.last
    assert_response :forbidden
    assert_equal "like", original.reload.kind
  end

  test "authorized nonmember admins can select on posts and replies" do
    sign_in users(:admin)
    reply = @club.club_messages.create!(parent: @message, user: @reader, body: "A reply")
    [ @message, reply ].each do |message|
      path = book_club_club_message_reaction_path(@club, message)
      get path
      assert_response :success
      put path, params: { kind: "wow" }, as: :turbo_stream
      assert_response :success
      assert_equal "wow", message.reactions.find_by!(user: users(:admin)).kind
    end
  end

  test "cross book and cross club targets return not found for every action" do
    sign_in @reader
    wrong_paths = [
      book_review_reaction_path(books(:pragmatic), @review),
      book_club_club_message_reaction_path(BookClub.create!(name: "Other HTTP club").tap { |club| club.book_club_memberships.create!(user: @reader, role: "member") }, @message)
    ]
    wrong_paths.each do |path|
      sign_in @reader
      get path
      assert_response :not_found
      sign_in @reader
      put path, params: { kind: "like" }
      assert_response :not_found
      sign_in @reader
      delete path
      assert_response :not_found
    end
  end

  test "soft deleted posts reject every reaction action while retained replies remain selectable" do
    sign_in @reader
    reply = @club.club_messages.create!(parent: @message, user: @reader, body: "Retained reply")
    @message.remove_from_discussion!
    get @paths.last
    assert_response :not_found
    sign_in @reader
    put @paths.last, params: { kind: "like" }
    assert_response :not_found
    sign_in @reader
    delete @paths.last
    assert_response :not_found
    sign_in @reader
    put book_club_club_message_reaction_path(@club, reply), params: { kind: "love" }, as: :turbo_stream
    assert_response :success
    assert_equal "love", reply.reactions.sole.kind
  end

  test "hard deleted targets return not found instead of creating reactions" do
    sign_in @reader
    @message.destroy!
    @review.destroy!
    @book.destroy!
    @paths.each do |path|
      sign_in @reader
      get path
      assert_response :not_found
      sign_in @reader
      put path, params: { kind: "like" }
      assert_response :not_found
      sign_in @reader
      delete path
      assert_response :not_found
    end
  end

  test "reaction writes retain CSRF protection for all target types" do
    sign_in @reader
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @targets.zip(@paths).each do |target, path|
      sign_in @reader
      get book_path(@book)
      assert_response :success
      token = css_select("meta[name='csrf-token']").first["content"]
      put path, params: { kind: "like" }, headers: { "X-CSRF-Token" => token, "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      reaction = target.reactions.find_by!(user: @reader)
      delete path
      assert_response :unprocessable_entity
      assert reaction.reload.persisted?
      sign_in @reader
      put path, params: { kind: "love" }
      assert_response :unprocessable_entity
      assert_equal "like", reaction.reload.kind
      sign_in @reader
      get book_path(@book)
      token = css_select("meta[name='csrf-token']").first["content"]
      delete path, headers: { "X-CSRF-Token" => token, "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_empty target.reactions.reload
    end
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
