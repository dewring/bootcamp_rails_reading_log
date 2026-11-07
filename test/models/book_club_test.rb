require "test_helper"

class BookClubTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "valid book club is valid" do
    assert BookClub.new(name: "Sci-Fi Society").valid?
  end

  test "name must be present" do
    assert_not BookClub.new(name: "").valid?
  end

  test "public creation requires a description but not a current book or deadline" do
    club = BookClub.new(name: "New club", description: "   ")
    assert_not club.valid?(:public_creation)
    assert_includes club.errors[:description], "can't be blank"
    club.description = "Read together."
    assert club.valid?(:public_creation)
  end

  test "leaderboard ranks members by furthest page reached, not total pages logged" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    leader = users(:leika)
    runner_up = users(:jaina)
    book_club.book_club_memberships.create!(user: leader, role: "owner")
    book_club.book_club_memberships.create!(user: runner_up, role: "member")

    # runner_up logged more sessions but never read as far into the book
    ReadingSession.create!(user: runner_up, book: books(:refactoring), read_on: 2.days.ago, pages_read: 30)
    ReadingSession.create!(user: runner_up, book: books(:refactoring), read_on: Date.today, pages_read: 40)
    ReadingSession.create!(user: leader, book: books(:refactoring), read_on: Date.today, pages_read: 60)

    assert_equal [ leader, runner_up ], book_club.leaderboard.to_a
    assert_equal 60, book_club.leaderboard.first.furthest_page_read.to_i
  end

  test "leaderboard excludes non-members even for the same book" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    member = users(:leika)
    outsider = users(:jaina)
    book_club.book_club_memberships.create!(user: member, role: "owner")

    ReadingSession.create!(user: member, book: books(:refactoring), read_on: Date.today, pages_read: 10)
    ReadingSession.create!(user: outsider, book: books(:refactoring), read_on: Date.today, pages_read: 999)

    assert_equal [ member ], book_club.leaderboard.to_a
  end

  test "leaderboard excludes sessions for books other than the current pick" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    member = users(:jaina)
    book_club.book_club_memberships.create!(user: member, role: "owner")

    ReadingSession.create!(user: member, book: books(:refactoring), read_on: Date.today, pages_read: 10)
    ReadingSession.create!(user: member, book: books(:pragmatic), read_on: Date.today, pages_read: 999)

    assert_equal 10, book_club.leaderboard.first.furthest_page_read.to_i
  end

  test "leaderboard gives tied members the same rank" do
    current_book = Book.create!(title: "Leaderboard Tie Book", author: "Test Author")
    book_club = BookClub.create!(name: "Tie Test Club", current_book: current_book)
    member_one = users(:leika)
    member_two = users(:jaina)
    book_club.book_club_memberships.create!(user: member_one, role: "owner")
    book_club.book_club_memberships.create!(user: member_two, role: "member")
    ReadingSession.create!(user: member_one, book: current_book, read_on: Date.today, pages_read: 50)
    ReadingSession.create!(user: member_two, book: current_book, read_on: Date.today, pages_read: 50)

    ranks = book_club.leaderboard.map(&:rank)

    assert_equal [ 1, 1 ], ranks
  end

  test "changing the current pick refreshes both live panels after commit" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(current_book: books(:pragmatic))

    assert_enqueued_with(job: BookClubCurrentPickJob, args: [ book_club.id ])
    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ book_club.id ])
  end

  test "changing to a different current pick notifies every current member" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    owner = users(:leika)
    member = users(:jaina)
    book_club.book_club_memberships.create!(user: owner, role: "owner")
    book_club.book_club_memberships.create!(user: member, role: "member")
    clear_enqueued_jobs

    assert_enqueued_with(job: Noticed::EventJob) do
      book_club.update!(current_book: books(:pragmatic))
    end

    event = Noticed::Event.order(created_at: :desc).first
    assert_equal [ owner.id, member.id ].sort, event.notifications.pluck(:recipient_id).sort
    assert_equal "Sci-Fi Society", event.params[:book_club_name]
    assert_equal books(:pragmatic).title, event.params[:book_title]
  end

  test "unchanged club details and description changes do not create notifications" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    clear_enqueued_jobs

    assert_no_difference("Noticed::Event.count") do
      book_club.update!(current_book: books(:refactoring))
      book_club.update!(name: book_club.name, reading_deadline: book_club.reading_deadline)
      book_club.update!(description: "A new description")
    end
  end

  test "renaming a club notifies the owner and current members with both names" do
    book_club = BookClub.create!(name: "Old circle")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    book_club.book_club_memberships.create!(user: users(:jaina), role: "member")

    assert_difference "BookClubRenameNotifier.count", 1 do
      book_club.update!(name: "New circle")
    end

    event = BookClubRenameNotifier.last
    assert_equal [ users(:leika).id, users(:jaina).id ].sort, event.notifications.pluck(:recipient_id).sort
    assert_equal "Old circle", event.params[:previous_name]
    assert_equal "New circle", event.params[:book_club_name]
    assert event.notifications.all?(&:unread?)
  end

  test "setting and clearing a deadline notifies current members with each saved value" do
    book_club = BookClub.create!(name: "Deadline circle")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    assert_difference "BookClubDeadlineNotifier.count", 2 do
      book_club.update!(reading_deadline: Date.new(2026, 12, 15))
      book_club.update!(reading_deadline: nil)
    end

    events = BookClubDeadlineNotifier.where(record: book_club).order(:id)
    assert_equal [ "2026-12-15", nil ], events.map { |event| event.params[:reading_deadline] }
    events.each do |event|
      assert_equal [ users(:leika).id ], event.notifications.pluck(:recipient_id)
    end
  end

  test "clearing the current pick notifies current members with an empty book snapshot" do
    book_club = BookClub.create!(name: "Pick circle", current_book: books(:refactoring))
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    assert_difference "BookClubPickNotifier.count", 1 do
      book_club.update!(current_book: nil)
    end

    event = BookClubPickNotifier.last
    assert_nil event.params[:book_title]
    assert_equal [ users(:leika).id ], event.notifications.pluck(:recipient_id)
    assert_equal "Pick circle cleared its current pick.", event.notifications.first.message
  end

  test "changing name pick and deadline together creates one event for each field" do
    book_club = BookClub.create!(name: "Old circle")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    assert_difference "Noticed::Event.count", 3 do
      book_club.update!(name: "New circle", current_book: books(:refactoring), reading_deadline: Date.new(2026, 12, 15))
    end

    events = Noticed::Event.where(record: book_club)
    assert_equal [ "BookClubDeadlineNotifier", "BookClubPickNotifier", "BookClubRenameNotifier" ], events.pluck(:type).sort
    assert events.all? { |event| event.params[:book_club_name] == "New circle" }
    assert events.all? { |event| event.notifications.pluck(:recipient_id) == [ users(:leika).id ] }
  end

  test "club changes do not notify former members or nonmembers" do
    book_club = BookClub.create!(name: "Members only")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    former_membership = book_club.book_club_memberships.create!(user: users(:jaina), role: "member")
    former_membership.destroy!

    book_club.update!(name: "Current members only", reading_deadline: Date.new(2026, 12, 15))

    Noticed::Event.where(record: book_club).each do |event|
      assert_equal [ users(:leika).id ], event.notifications.pluck(:recipient_id)
    end
  end

  test "club changes without members do not create empty notification events" do
    book_club = BookClub.create!(name: "Empty circle")

    assert_no_difference "Noticed::Event.count" do
      book_club.update!(name: "Renamed empty circle", reading_deadline: Date.new(2026, 12, 15))
    end
  end

  test "rolled back club detail changes do not create notification events" do
    book_club = BookClub.create!(name: "Rollback circle")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    clear_enqueued_jobs

    assert_no_difference "Noticed::Event.count" do
      BookClub.transaction do
        book_club.update!(name: "Not committed", current_book: books(:refactoring), reading_deadline: Date.new(2026, 12, 15))
        raise ActiveRecord::Rollback
      end
    end
    assert_no_enqueued_jobs(only: Noticed::EventJob)
  end

  test "does not notify after a failed update" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    clear_enqueued_jobs

    assert_no_difference("Noticed::Event.count") do
      assert_not book_club.update(name: "")
    end
  end

  test "clearing the current pick refreshes both live panels after commit" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(current_book: nil)

    assert_enqueued_with(job: BookClubCurrentPickJob, args: [ book_club.id ])
    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ book_club.id ])
  end

  test "changing only the deadline refreshes the current-pick panel" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(reading_deadline: Date.current + 7.days)

    assert_enqueued_with(job: BookClubCurrentPickJob, args: [ book_club.id ])
    assert_no_enqueued_jobs(only: BookClubLeaderboardJob)
  end

  test "unrelated club changes do not refresh live panels" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    book_club.update!(name: "New Name")

    assert_no_enqueued_jobs(only: [ BookClubCurrentPickJob, BookClubLeaderboardJob ])
  end

  test "club panel jobs are not enqueued when the update rolls back" do
    book_club = BookClub.create!(name: "Sci-Fi Society", current_book: books(:refactoring))
    clear_enqueued_jobs

    BookClub.transaction do
      book_club.update!(current_book: books(:pragmatic))
      raise ActiveRecord::Rollback
    end

    assert_no_enqueued_jobs(only: [ BookClubCurrentPickJob, BookClubLeaderboardJob ])
    assert_equal books(:refactoring), book_club.reload.current_book
  end
end
