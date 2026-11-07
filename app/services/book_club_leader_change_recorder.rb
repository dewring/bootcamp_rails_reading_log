class BookClubLeaderChangeRecorder
  def initialize(book_club_id:)
    @book_club_id = book_club_id
  end

  def record_leader_change
    BookClub.transaction do
      # Keep pick changes, membership counter updates, and club deletion outside this comparison.
      # Other clubs can still record their leaders independently.
      club = BookClub.lock("FOR SHARE").find_by(id: @book_club_id)
      return unless club

      snapshot = BookClubLeaderboardSnapshot.find_or_create_by!(book_club: club)
      # Serialize this club's snapshot so concurrent jobs cannot announce the same transition twice.
      snapshot.with_lock do
        record_current_leaders(club, snapshot)
      end
    end
  end

  private

  def record_current_leaders(club, snapshot)
    leaders = club.leaderboard.to_a.select { |reader| reader.rank.to_i == 1 }.sort_by(&:id)
    leader_ids = leaders.map(&:id)

    # A missing pick, first snapshot, or different pick establishes a baseline without an alert.
    if club.current_book_id.nil? || snapshot.current_book_id != club.current_book_id
      snapshot.update!(current_book_id: club.current_book_id, leader_user_ids: leader_ids)
      return
    end
    return if snapshot.leader_user_ids == leader_ids

    snapshot.update!(leader_user_ids: leader_ids)
    notify_members_of_leader_change(club, leaders)
  end

  def notify_members_of_leader_change(club, leaders)
    recipients = club.users.to_a
    return if recipients.empty?

    event = BookClubLeaderNotifier.with(
      record: club,
      book_club_name: club.name,
      book_title: club.current_book.title,
      leader_names: leaders.map(&:nickname)
    ).deliver(recipients, enqueue_job: false)

    # The separate queue database must not start delivery before the snapshot and event commit.
    ActiveRecord.after_all_transactions_commit do
      Noticed::EventJob.perform_later(event)
    end
    event
  end
end
