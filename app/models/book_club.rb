class BookClub < ApplicationRecord
  audited

  belongs_to :current_book, class_name: "Book", optional: true
  has_many :book_club_memberships, dependent: :destroy
  has_many :users, through: :book_club_memberships
  has_many :club_messages, dependent: :destroy

  after_commit :refresh_live_panels, on: :update
  after_commit :notify_members_of_new_pick, on: :update

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

  def notify_members_of_new_pick
    return unless current_pick_changed_to_book?

    BookClubPickNotifier.with(
      record: self,
      book_club_name: name,
      book_title: current_book.title
    ).deliver(current_members)
  end

  def current_pick_changed_to_book?
    saved_change_to_current_book_id? && current_book_id.present? && saved_change_to_current_book_id.first != current_book_id
  end

  def current_members
    book_club_memberships.includes(:user).map(&:user)
  end

  def refresh_live_panels
    BookClubCurrentPickJob.perform_later(id) if saved_change_to_current_book_id? || saved_change_to_reading_deadline?
    BookClubLeaderboardJob.perform_later(id) if saved_change_to_current_book_id?
  end
end
