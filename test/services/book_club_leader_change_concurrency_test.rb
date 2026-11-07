require "test_helper"
require "timeout"

class BookClubLeaderChangeConcurrencyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @book = Book.create!(title: "Concurrent leaderboard", author: "An Author")
    @books = [ @book ]
    @club = create_club("Concurrent circle")
    @clubs = [ @club ]
    ReadingSession.create!(user: users(:leika), book: @book, read_on: Date.current, pages_read: 10)
  end

  teardown do
    Noticed::Event.where(record_type: "BookClub", record_id: @clubs.map(&:id)).destroy_all
    @clubs.each(&:destroy!)
    @books.each(&:destroy!)
  end

  test "concurrent first observations recover a unique snapshot creation collision" do
    arrived = Queue.new
    release = Queue.new
    before_insert = -> {
      arrived.push(true)
      release.pop
    }
    BookClubLeaderboardSnapshot.set_callback(:create, :before, before_insert)
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          record_change(@club)
        end
      end
    end

    2.times { Timeout.timeout(10) { arrived.pop } }
    2.times { release.push(true) }
    workers.each { |worker| Timeout.timeout(10) { worker.value } }

    assert_equal 1, BookClubLeaderboardSnapshot.where(book_club: @club).count
    assert_equal [ users(:leika).id ], @club.reload.leaderboard_snapshot.leader_user_ids
    assert_equal 0, BookClubLeaderNotifier.where(record: @club).count
  ensure
    BookClubLeaderboardSnapshot.skip_callback(:create, :before, before_insert) if before_insert
    2.times { release.push(true) } if release
    workers&.each { |worker| Timeout.timeout(10) { worker.value } }
  end

  test "a locked snapshot blocks the same club and a retry announces the transition only once" do
    record_change(@club)
    ReadingSession.create!(user: users(:jaina), book: @book, read_on: Date.current, pages_read: 20)

    with_locked_snapshot(@club) do
      assert_raises ActiveRecord::LockWaitTimeout do
        with_short_lock_timeout { record_change(@club) }
      end
    end

    assert_difference "BookClubLeaderNotifier.count", 1 do
      record_change(@club)
      assert_nil record_change(@club)
    end
    assert_equal [ users(:jaina).id ], @club.reload.leaderboard_snapshot.leader_user_ids
  end

  test "another club with the same readers can record a leader change while this snapshot is locked" do
    other_club = create_club("Independent circle")
    @clubs.push(other_club)
    record_change(@club)
    record_change(other_club)
    ReadingSession.create!(user: users(:jaina), book: @book, read_on: Date.current, pages_read: 20)

    with_locked_snapshot(@club) do
      with_short_lock_timeout do
        assert_difference "BookClubLeaderNotifier.where(record: other_club).count", 1 do
          record_change(other_club)
        end
      end
    end

    assert_equal [ users(:jaina).id ], other_club.reload.leaderboard_snapshot.leader_user_ids
    assert_equal [ users(:leika).id ], @club.reload.leaderboard_snapshot.leader_user_ids
  end

  test "pick changes and deletion wait for the comparison while another club can change its pick" do
    record_change(@club)
    other_club = create_club("Independent pick circle")
    @clubs.push(other_club)
    next_book = Book.create!(title: "Independent next pick", author: "An Author")
    @books.push(next_book)
    ready = Queue.new
    release = Queue.new
    original_lookup = BookClubLeaderboardSnapshot.method(:find_or_create_by!)
    before_snapshot = ->(attributes) {
      ready.push(true)
      release.pop
      original_lookup.call(attributes)
    }

    BookClubLeaderboardSnapshot.stub(:find_or_create_by!, before_snapshot) do
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { record_change(@club) }
      end
      begin
        Timeout.timeout(10) { ready.pop }
        assert_raises ActiveRecord::LockWaitTimeout do
          with_short_lock_timeout { BookClub.find(@club.id).update!(current_book: next_book) }
        end
        assert_raises ActiveRecord::LockWaitTimeout do
          with_short_lock_timeout { BookClub.find(@club.id).destroy! }
        end
        with_short_lock_timeout { other_club.update!(current_book: next_book) }
        assert_equal next_book.id, other_club.reload.current_book_id
      ensure
        release.push(true)
        Timeout.timeout(10) { worker.value }
      end
    end

    assert_equal @book.id, @club.reload.current_book_id
    assert_equal 2, @club.book_club_memberships.count
  end

  private

  def create_club(name)
    club = BookClub.create!(name: name, current_book: @book)
    club.book_club_memberships.create!(user: users(:leika), role: "owner")
    club.book_club_memberships.create!(user: users(:jaina), role: "member")
    club
  end

  def record_change(club)
    BookClubLeaderChangeRecorder.new(book_club_id: club.id).record_leader_change
  end

  def with_short_lock_timeout
    connection = ActiveRecord::Base.connection
    connection.execute("SET lock_timeout = '250ms'")
    yield
  ensure
    connection.execute("RESET lock_timeout")
  end

  def with_locked_snapshot(club)
    ready = Queue.new
    release = Queue.new
    locker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        BookClubLeaderboardSnapshot.find_by!(book_club: club).with_lock do
          ready.push(true)
          release.pop
        end
      end
    end
    Timeout.timeout(10) { ready.pop }
    yield
  ensure
    release.push(true)
    Timeout.timeout(10) { locker.value }
  end
end
