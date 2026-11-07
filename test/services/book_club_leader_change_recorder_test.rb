require "test_helper"

class BookClubLeaderChangeRecorderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @book = Book.create!(title: "Leaderboard book", author: "An Author")
    @club = BookClub.create!(name: "Leaderboard circle", current_book: @book)
    @owner = users(:leika)
    @member = users(:jaina)
    @club.book_club_memberships.create!(user: @owner, role: "owner")
    @club.book_club_memberships.create!(user: @member, role: "member")
    @owner_session = ReadingSession.create!(user: @owner, book: @book, read_on: Date.current, pages_read: 10)
  end

  test "the first observation stores a baseline without announcing an existing leader" do
    assert_no_difference "BookClubLeaderNotifier.count" do
      assert_nil record_change
    end

    snapshot = @club.reload.leaderboard_snapshot
    assert_equal @book.id, snapshot.current_book_id
    assert_equal [ @owner.id ], snapshot.leader_user_ids
  end

  test "a new first place reader notifies current members including the new leader" do
    record_change
    ReadingSession.create!(user: @member, book: @book, read_on: Date.current, pages_read: 20)
    clear_enqueued_jobs

    event = nil
    assert_difference "BookClubLeaderNotifier.count", 1 do
      assert_enqueued_with(job: Noticed::EventJob) do
        event = record_change
      end
    end

    assert_equal [ @owner.id, @member.id ].sort, event.notifications.pluck(:recipient_id).sort
    assert_equal [ @member.nickname ], event.params[:leader_names]
    assert_equal @club.name, event.params[:book_club_name]
    assert_equal @book.title, event.params[:book_title]
    assert_equal [ @member.id ], @club.reload.leaderboard_snapshot.leader_user_ids
  end

  test "repeated jobs and higher scores by the same leader do not create more notifications" do
    record_change
    @owner_session.update!(pages_read: 30)

    assert_no_difference "BookClubLeaderNotifier.count" do
      2.times { assert_nil record_change }
    end
  end

  test "entering and leaving a tie notifies changes to the complete first place set" do
    record_change
    member_session = ReadingSession.create!(user: @member, book: @book, read_on: Date.current, pages_read: 10)
    tied_event = record_change

    assert_equal [ @owner.id, @member.id ].sort, @club.reload.leaderboard_snapshot.leader_user_ids
    expected_names = [ @owner, @member ].sort_by(&:id).map(&:nickname)
    assert_equal expected_names, tied_event.params[:leader_names]

    @owner_session.update!(pages_read: 20)
    member_session.update!(pages_read: 20)
    assert_no_difference "BookClubLeaderNotifier.count" do
      assert_nil record_change
    end

    @owner_session.update!(pages_read: 30)
    sole_event = record_change
    assert_equal [ @owner.nickname ], sole_event.params[:leader_names]
    assert_equal [ @owner.id ], @club.reload.leaderboard_snapshot.leader_user_ids
  end

  test "a retry after a recorded transition does not create another event or notification" do
    record_change
    ReadingSession.create!(user: @member, book: @book, read_on: Date.current, pages_read: 20)
    event = record_change
    notification = event.notifications.find_by!(recipient: @owner)
    notification.mark_as_read!
    read_at = notification.read_at
    clear_enqueued_jobs

    assert_no_difference [ "Noticed::Event.count", "Noticed::Notification.count" ] do
      2.times { assert_nil record_change }
    end
    assert_no_enqueued_jobs(only: Noticed::EventJob)
    assert_equal read_at, notification.reload.read_at
  end

  test "changing or clearing the current book establishes a new baseline without a leader alert" do
    record_change
    next_book = Book.create!(title: "Next leaderboard book", author: "An Author")
    ReadingSession.create!(user: @member, book: next_book, read_on: Date.current, pages_read: 50)

    assert_no_difference "BookClubLeaderNotifier.count" do
      @club.update!(current_book: next_book)
      assert_nil record_change
      assert_equal [ @member.id ], @club.reload.leaderboard_snapshot.leader_user_ids
      assert_equal next_book.id, @club.leaderboard_snapshot.current_book_id

      @club.update!(current_book: nil)
      assert_nil record_change
      assert_empty @club.reload.leaderboard_snapshot.leader_user_ids
      assert_nil @club.leaderboard_snapshot.current_book_id
    end
  end

  test "the first reader after an observed empty ranking is a leader change" do
    @owner_session.destroy!
    record_change
    ReadingSession.create!(user: @member, book: @book, read_on: Date.current, pages_read: 20)

    assert_difference "BookClubLeaderNotifier.count", 1 do
      assert_equal [ @member.nickname ], record_change.params[:leader_names]
    end
  end

  test "deleting a cleared pick before the next observation resets its historical leaders without an alert" do
    record_change
    @club.update!(current_book: nil)
    @book.destroy!

    assert_no_difference "BookClubLeaderNotifier.count" do
      assert_nil record_change
    end
    assert_nil @club.reload.leaderboard_snapshot.current_book_id
    assert_empty @club.leaderboard_snapshot.leader_user_ids
  end

  test "removing the last ranked session notifies remaining members about the empty ranking" do
    record_change
    @owner_session.destroy!
    event = record_change

    assert_empty event.params[:leader_names]
    assert_equal [ @owner.id, @member.id ].sort, event.notifications.pluck(:recipient_id).sort
    assert_empty @club.reload.leaderboard_snapshot.leader_user_ids
  end

  test "a departed leader is replaced and only current members receive the alert" do
    ReadingSession.create!(user: @member, book: @book, read_on: Date.current, pages_read: 5)
    record_change
    @club.book_club_memberships.find_by!(user: @owner).destroy!
    event = record_change

    assert_equal [ @member.nickname ], event.params[:leader_names]
    assert_equal [ @member.id ], event.notifications.pluck(:recipient_id)
  end

  test "a nonmember reading the same book does not change the club leader set" do
    record_change
    ReadingSession.create!(user: users(:admin), book: @book, read_on: Date.current, pages_read: 999)

    assert_no_difference "BookClubLeaderNotifier.count" do
      assert_nil record_change
    end
  end

  test "an empty membership records the new snapshot without an empty notification event" do
    record_change
    @club.book_club_memberships.destroy_all

    assert_no_difference "BookClubLeaderNotifier.count" do
      assert_nil record_change
    end
    assert_empty @club.reload.leaderboard_snapshot.leader_user_ids
  end

  test "a failed event creation rolls back the snapshot so a retry can announce the change once" do
    record_change
    ReadingSession.create!(user: @member, book: @book, read_on: Date.current, pages_read: 20)
    clear_enqueued_jobs

    assert_no_difference "BookClubLeaderNotifier.count" do
      BookClubLeaderNotifier.stub(:with, ->(*) { raise "Notification persistence failed" }) do
        assert_raises(RuntimeError) { record_change }
      end
    end
    assert_equal [ @owner.id ], @club.reload.leaderboard_snapshot.leader_user_ids
    assert_no_enqueued_jobs(only: Noticed::EventJob)

    assert_difference "BookClubLeaderNotifier.count", 1 do
      record_change
      assert_nil record_change
    end
  end

  test "delivery waits for the outer transaction and rollback preserves the previous snapshot" do
    record_change
    ReadingSession.create!(user: @member, book: @book, read_on: Date.current, pages_read: 20)
    clear_enqueued_jobs

    assert_no_difference "BookClubLeaderNotifier.count" do
      BookClub.transaction(requires_new: true) do
        record_change
        assert_no_enqueued_jobs(only: Noticed::EventJob)
        raise ActiveRecord::Rollback
      end
    end
    assert_equal [ @owner.id ], @club.reload.leaderboard_snapshot.leader_user_ids
    assert_no_enqueued_jobs(only: Noticed::EventJob)

    assert_enqueued_with(job: Noticed::EventJob) do
      BookClub.transaction(requires_new: true) do
        record_change
        assert_no_enqueued_jobs(only: Noticed::EventJob)
      end
    end
  end

  test "a deleted club does not create a snapshot or notification" do
    @club.destroy!

    assert_no_difference [ "BookClubLeaderboardSnapshot.count", "BookClubLeaderNotifier.count" ] do
      assert_nil record_change
    end
  end

  private

  def record_change
    BookClubLeaderChangeRecorder.new(book_club_id: @club.id).record_leader_change
  end
end
