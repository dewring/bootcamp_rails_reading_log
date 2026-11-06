require "test_helper"
require "timeout"

class ReactionSelectionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @reader = User.create!(first_name: "Concurrent", last_name: "Reader", email: "concurrent-reactions@example.test", nickname: "concurrent_reactions", password: "test-password-143")
    @book = Book.create!(title: "Concurrent selection", author: "Test author")
    @review = Review.create!(book: @book, user: users(:admin), rating: 4, body: "A reflection")
    @club = BookClub.create!(name: "Concurrent reaction discussion")
    @club.book_club_memberships.create!(user: @reader, role: "member")
    @message = @club.club_messages.create!(user: users(:admin), body: "A thought")
  end

  teardown do
    @reader&.destroy!
    @club&.destroy!
    @book&.destroy!
  end

  test "concurrent first inserts retry database uniqueness collisions and return the same reaction" do
    [ @book, @review, @message ].each do |target|
      ids = concurrent_first_selections(target, checkpoint: :create)

      assert_equal 1, ids.uniq.length
      assert_equal [ ids.first ], target.reactions.where(user_id: @reader.id).pluck(:id)
    end
  end

  test "concurrent first selections retry model uniqueness failures and return the same reaction" do
    [ @book, @review, @message ].each do |target|
      ids = concurrent_first_selections(target, checkpoint: :validation)

      assert_equal 1, ids.uniq.length
      assert_equal [ ids.first ], target.reactions.where(user_id: @reader.id).pluck(:id)
    end
  end

  test "different readers can select on the same target before the first reader commits" do
    other = users(:jaina)
    @club.book_club_memberships.create!(user: other, role: "member")

    [ @book, @review, @message ].each do |target|
      with_pending_selection(target) do
        contender = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.execute("SET lock_timeout = '2s'")
            begin
              user = User.find(other.id)
              record = target.class.find(target.id)
              ReactionSelection.new(user: user, target: record).select_kind(kind: "love").id
            ensure
              connection.execute("RESET lock_timeout")
            end
          end
        end
        id = Timeout.timeout(10) { contender.value }

        assert target.reactions.exists?(id)
      end

      assert_equal 2, target.reactions.count
    end
  end

  test "the same reader can react to another book review and message before the first selection commits" do
    other_book = Book.create!(title: "Independent selection", author: "Test author")

    with_pending_selection(@book) do
      [ other_book, @review, @message ].each do |target|
        contender = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.execute("SET lock_timeout = '2s'")
            begin
              user = User.find(@reader.id)
              record = target.class.find(target.id)
              ReactionSelection.new(user: user, target: record).select_kind(kind: "love").id
            ensure
              connection.execute("RESET lock_timeout")
            end
          end
        end

        id = Timeout.timeout(10) { contender.value }
        assert target.reactions.exists?(id)
      end
    end
  ensure
    other_book&.destroy!
  end

  test "an existing reaction is locked until its pending update commits" do
    [ @book, @review, @message ].each do |target|
      original = ReactionSelection.new(user: @reader, target: target).select_kind(kind: "love")
      with_pending_selection(target) do
        assert_raises(ActiveRecord::LockWaitTimeout) do
          target.class.transaction(requires_new: true) do
            target.class.connection.execute("SET LOCAL lock_timeout = '250ms'")
            ReactionSelection.new(user: User.find(@reader.id), target: target.class.find(target.id)).select_kind(kind: "wow")
          end
        end
      end

      switched = ReactionSelection.new(user: @reader, target: target).select_kind(kind: "wow")
      assert_equal original.id, switched.id
      assert_equal "wow", switched.kind
      assert_equal 1, target.reactions.where(user: @reader).count
    end
  end

  test "a shared target lock blocks post deletion until the selection commits" do
    with_pending_selection(@message) do
      assert_raises(ActiveRecord::LockWaitTimeout) do
        ClubMessage.transaction(requires_new: true) do
          ClubMessage.connection.execute("SET LOCAL lock_timeout = '250ms'")
          ClubMessage.find(@message.id).remove_from_discussion!
        end
      end
      assert_not @message.reload.deleted?
    end

    @message.remove_from_discussion!

    assert @message.reload.deleted?
    assert_empty @message.reactions.reload
  end

  private

  def concurrent_first_selections(target, checkpoint:)
    ready = Queue.new
    gates = Array.new(2) { Queue.new }
    reader_id = @reader.id
    model = target.reactions.klass
    pause_creation = ->(reaction) do
      gate = Thread.current[:reaction_creation_gate]
      if reaction.new_record? && reaction.user_id == reader_id && gate
        ready.push(nil)
        gate.pop
      end
    end
    model.set_callback(checkpoint, :before, pause_creation)
    threads = gates.map do |gate|
      Thread.new do
        Thread.current[:reaction_creation_gate] = gate
        ActiveRecord::Base.connection_pool.with_connection do
          user = User.find(reader_id)
          record = target.class.find(target.id)
          ReactionSelection.new(user: user, target: record).select_kind(kind: "like").id
        end
      rescue StandardError => error
        ready.push(error)
        raise
      ensure
        Thread.current[:reaction_creation_gate] = nil
      end
    end

    Timeout.timeout(15) do
      2.times do
        error = ready.pop
        raise error if error
      end
      gates.first.push(true)
      # In this case the second validator must see the first committed row.
      threads.first.value if checkpoint == :validation
      gates.last.push(true)
      threads.map(&:value)
    end
  ensure
    gates.each { |gate| gate.push(true) }
    threads&.each { |thread| thread.join(5) }
    model.skip_callback(checkpoint, :before, pause_creation)
  end

  def with_pending_selection(target)
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        user = User.find(@reader.id)
        record = target.class.find(target.id)
        record.class.transaction do
          ReactionSelection.new(user: user, target: record).select_kind(kind: "like")
          ready.push(nil)
          release.pop
        end
      end
    rescue StandardError => error
      ready.push(error)
      raise
    end

    Timeout.timeout(10) do
      error = ready.pop
      raise error if error

      yield
    end
  ensure
    release.push(true)
    Timeout.timeout(10) { holder.value }
  end
end
