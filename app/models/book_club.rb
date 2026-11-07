class BookClub < ApplicationRecord
  audited

  belongs_to :current_book, class_name: "Book", optional: true
  has_many :book_club_memberships, dependent: :destroy
  has_many :users, through: :book_club_memberships
  has_many :club_messages, dependent: :destroy
  has_one :leaderboard_snapshot, class_name: "BookClubLeaderboardSnapshot", dependent: :destroy

  after_commit :refresh_live_panels, on: :update
  after_commit :notify_members_of_club_changes, on: :update

  validates :name, presence: true
  validates :description, presence: true, on: :public_creation

  scope :matching_admin_text, ->(text) {
    return all if text.blank?

    query = "%#{sanitize_sql_like(text.to_s.strip)}%"
    left_joins(:current_book).where(<<~SQL.squish, query: query)
      book_clubs.name ILIKE :query OR book_clubs.description ILIKE :query
      OR books.title ILIKE :query OR books.author ILIKE :query
      OR EXISTS (
        SELECT 1 FROM book_club_memberships
        INNER JOIN users ON users.id = book_club_memberships.user_id
        WHERE book_club_memberships.book_club_id = book_clubs.id
          AND book_club_memberships.role = 'owner' AND users.nickname ILIKE :query
      )
    SQL
  }

  def preload_covers
    ActiveRecord::Associations::Preloader.new(
      records: [ self ],
      associations: { current_book: { cover_image_attachment: :blob } }
    ).call
  end

  def leaderboard
    users
      .joins(:reading_sessions)
      .where(reading_sessions: { book_id: current_book_id })
      .group("users.id")
      .order(Arel.sql("MAX(reading_sessions.pages_read) DESC"))
      .select(<<~SQL.squish)
        users.*,
        MAX(reading_sessions.pages_read) AS furthest_page_read,
        RANK() OVER (ORDER BY MAX(reading_sessions.pages_read) DESC) AS rank
      SQL
  end

  def pick_history
    audits
      .filter_map do |audit|
        next unless audit.audited_changes.key?("current_book_id")

        new_value = audit.audited_changes["current_book_id"]
        book_id = new_value.is_a?(Array) ? new_value.last : new_value
        next if book_id.blank?
        next if book_id.to_i == current_book_id

        { book: Book.find_by(id: book_id), changed_at: audit.created_at }
      end
      .reverse
  end

  private

  def notify_members_of_club_changes
    changes = saved_changes.slice("name", "current_book_id", "reading_deadline")
    return if changes.empty?

    recipients = current_members
    return if recipients.empty?

    notify_members_of_new_name(recipients) if changes.key?("name")
    notify_members_of_new_pick(recipients) if changes.key?("current_book_id")
    notify_members_of_reading_deadline(recipients) if changes.key?("reading_deadline")
  end

  def notify_members_of_new_name(recipients)
    BookClubRenameNotifier.with(
      record: self,
      previous_name: saved_change_to_name.first,
      book_club_name: name
    ).deliver(recipients)
  end

  def notify_members_of_new_pick(recipients)
    BookClubPickNotifier.with(
      record: self,
      book_club_name: name,
      book_title: current_book&.title
    ).deliver(recipients)
  end

  def notify_members_of_reading_deadline(recipients)
    BookClubDeadlineNotifier.with(
      record: self,
      book_club_name: name,
      reading_deadline: reading_deadline&.iso8601
    ).deliver(recipients)
  end

  def current_members
    book_club_memberships.includes(:user).map(&:user)
  end

  def refresh_live_panels
    BookClubCurrentPickJob.perform_later(id) if saved_change_to_current_book_id? || saved_change_to_reading_deadline?
    BookClubLeaderboardJob.perform_later(id) if saved_change_to_current_book_id?
  end
end
