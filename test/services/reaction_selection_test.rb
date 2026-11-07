require "test_helper"

class ReactionSelectionTest < ActiveSupport::TestCase
  setup do
    @reader = users(:leika)
    @book = Book.create!(title: "Selection target", author: "Test author")
    @review = Review.create!(book: @book, user: users(:admin), rating: 4, body: "A reflection")
    @club = BookClub.create!(name: "Selection discussion")
    @membership = @club.book_club_memberships.create!(user: @reader, role: "member")
    @message = @club.club_messages.create!(user: @reader, body: "A thought")
    @targets = [ @book, @review, @message ]
  end

  test "selection creates one reaction owned by the supplied current user for each target" do
    @targets.each do |target|
      reaction = selection(target).select_kind(kind: "love")

      assert reaction.persisted?
      assert_equal @reader.id, reaction.user_id
      assert_equal "love", reaction.kind
      assert_equal [ reaction.id ], target.reactions.pluck(:id)
    end
  end

  test "switching kind keeps the same reaction identity and advances its timestamp" do
    @targets.each do |target|
      original = selection(target).select_kind(kind: "like")
      original_time = original.updated_at

      travel 1.minute do
        switched = selection(target).select_kind(kind: "wow")

        assert_equal original.id, switched.id
        assert_equal "wow", switched.kind
        assert_operator switched.updated_at, :>, original_time
        assert_equal 1, target.reactions.count
      end
    end
  end

  test "repeating the same kind performs no SQL writes and preserves all reaction attributes" do
    @targets.each do |target|
      original = selection(target).select_kind(kind: "like")
      before = original.reload.attributes

      travel 1.minute do
        assert_no_sql_writes do
          repeated = selection(target).select_kind(kind: "like")
          assert_equal original.id, repeated.id
        end
      end

      assert_equal before, original.reload.attributes
    end
  end

  test "clear removes only the readers reaction and a repeated clear performs no SQL writes" do
    @targets.each do |target|
      own = selection(target).select_kind(kind: "like")
      other = target.reactions.create!(user: users(:jaina), kind: "love")

      assert selection(target).clear_selection.destroyed?
      assert_not target.reactions.exists?(own.id)
      assert target.reactions.exists?(other.id)
      assert_no_sql_writes { selection(target).clear_selection }
      assert_equal [ other.id ], target.reactions.pluck(:id)
    end
  end

  test "clearing an absent reaction never creates a record" do
    @targets.each do |target|
      assert_no_sql_writes { selection(target).clear_selection }
      assert_empty target.reactions.reload
    end
  end

  test "selection never adopts or changes another readers reaction" do
    @targets.each do |target|
      other = target.reactions.create!(user: users(:jaina), kind: "like")
      before = other.attributes
      own = selection(target).select_kind(kind: "love")

      assert_not_equal own.id, other.id
      assert_equal before, other.reload.attributes
      assert_equal @reader.id, own.user_id
    end
  end

  test "unknown and blank kinds reject selection without changing an existing reaction" do
    @targets.each do |target|
      original = selection(target).select_kind(kind: "like")
      before = original.attributes

      [ "unknown", "", nil ].each do |kind|
        assert_raises(ActiveRecord::RecordInvalid) { selection(target).select_kind(kind: kind) }
        assert_equal before, original.reload.attributes
      end
    end
  end

  test "disabled new selections fail while exact retries switching and clearing remain available" do
    originals = @targets.to_h { |target| [ target, selection(target).select_kind(kind: "like") ] }
    reaction_types(:like).update!(enabled: false)

    @targets.each do |target|
      before = originals.fetch(target).attributes
      assert_no_sql_writes { selection(target).select_kind(kind: "like") }
      assert_equal before, originals.fetch(target).reload.attributes

      selection(target).select_kind(kind: "love")
      assert_raises(ActiveRecord::RecordInvalid) { selection(target).select_kind(kind: "like") }
      selection(target).clear_selection
      assert_raises(ActiveRecord::RecordInvalid) { selection(target).select_kind(kind: "like") }
      assert_empty target.reactions.reload
    end
  end

  test "catalog eligibility is read from the database rather than a cached enabled type" do
    type = reaction_types(:love)
    assert type.enabled?
    ReactionType.where(id: type.id).update_all(enabled: false)

    @targets.each do |target|
      assert_raises(ActiveRecord::RecordInvalid) { selection(target).select_kind(kind: type.key) }
      assert_empty target.reactions.reload
    end
  end

  test "an existing disabled choice can be cleared directly" do
    @targets.each { |target| selection(target).select_kind(kind: "like") }
    reaction_types(:like).update!(enabled: false)

    @targets.each do |target|
      assert selection(target).clear_selection.destroyed?
      assert_empty target.reactions.reload
      assert_no_sql_writes { selection(target).clear_selection }
    end
  end

  test "a catalog added kind can be selected without changing the selection service" do
    type = ReactionType.create!(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: true)

    @targets.each do |target|
      reaction = selection(target).select_kind(kind: type.key)

      assert_equal "celebrate", reaction.reload.kind
      assert_equal type, reaction.reaction_type
    end
  end

  test "a reply remains independently selectable after its parent post is deleted" do
    reply = @club.club_messages.create!(parent: @message, user: @reader, body: "An answer")
    selection(@message).select_kind(kind: "like")
    original = selection(reply).select_kind(kind: "love")
    @message.remove_from_discussion!

    changed = selection(reply).select_kind(kind: "wow")

    assert_equal original.id, changed.id
    assert_equal "wow", changed.kind
    assert_empty @message.reactions.reload
    assert selection(reply).clear_selection.destroyed?
  end

  test "stale active user objects cannot mutate reactions after their account becomes inactive" do
    @targets.each { |target| selection(target).select_kind(kind: "like") }

    [ "invited", "suspended" ].each do |status|
      @reader.update!(account_status: "active")
      stale_user = User.find(@reader.id)
      User.find(@reader.id).update!(account_status: status)

      @targets.each do |target|
        service = ReactionSelection.new(user: stale_user, target: target)
        assert_no_sql_writes do
          assert_raises(Pundit::NotAuthorizedError) { service.select_kind(kind: "like") }
          assert_raises(Pundit::NotAuthorizedError) { service.select_kind(kind: "love") }
          assert_raises(Pundit::NotAuthorizedError) { service.clear_selection }
        end
        assert_equal "like", target.reactions.find_by!(user_id: @reader.id).kind
      end
    end
  end

  test "former club members cannot select or clear using a previously loaded message" do
    service = selection(@message)
    service.select_kind(kind: "like")
    @membership.destroy!

    assert_no_sql_writes do
      assert_raises(Pundit::NotAuthorizedError) { service.select_kind(kind: "love") }
      assert_raises(Pundit::NotAuthorizedError) { service.clear_selection }
    end
    assert_equal "like", @message.reactions.sole.kind
  end

  test "a nonmember admin can select on a readable Discussion message" do
    reaction = ReactionSelection.new(user: users(:admin), target: @message).select_kind(kind: "wow")

    assert_equal users(:admin).id, reaction.user_id
    assert_equal "wow", reaction.kind
  end

  test "a soft deleted post cannot receive a new reaction" do
    service = selection(@message)
    @message.remove_from_discussion!

    assert_raises(Pundit::NotAuthorizedError) { service.select_kind(kind: "love") }
    assert_empty @message.reactions.reload
  end

  test "a concurrently deleted target refuses selection rather than recreating it" do
    stale_target = Book.find(@book.id)
    @book.destroy!

    assert_raises(ActiveRecord::RecordNotFound) { selection(stale_target).select_kind(kind: "love") }
    assert_not Book.exists?(stale_target.id)
    assert_empty Reaction.where(book_id: stale_target.id)
  end

  test "a rolled back selection does not persist" do
    @targets.each do |target|
      target.class.transaction(requires_new: true) do
        selection(target).select_kind(kind: "love")
        raise ActiveRecord::Rollback
      end

      assert_empty target.reactions.reload
    end
  end

  private

  def selection(target)
    ReactionSelection.new(user: @reader, target: target)
  end

  def assert_no_sql_writes
    writes = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      writes.push(payload.fetch(:sql)) if payload.fetch(:sql).match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    assert_empty writes
  end
end
