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

  test "simultaneous first selections return the same single row for each target type" do
    [ @book, @review, @message ].each do |target|
      ready = Queue.new
      start = Queue.new
      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready.push(true)
            start.pop
            user = User.find(@reader.id)
            record = target.class.find(target.id)
            ReactionSelection.new(user: user, target: record).select_kind(kind: "like").id
          end
        end
      end

      ids = Timeout.timeout(15) do
        2.times { ready.pop }
        2.times { start.push(true) }
        threads.map(&:value)
      end

      assert_equal 1, ids.uniq.length
      assert_equal [ ids.first ], target.reactions.where(user_id: @reader.id).pluck(:id)
    ensure
      2.times { start.push(true) }
      threads.each { |thread| thread.join(5) }
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

  def with_pending_selection(target)
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        user = User.find(@reader.id)
        record = target.class.find(target.id)
        user.with_lock do
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
