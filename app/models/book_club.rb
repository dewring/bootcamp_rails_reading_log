class BookClub < ApplicationRecord
  audited

  belongs_to :current_book, class_name: "Book", optional: true
  has_many :book_club_memberships, dependent: :destroy
  has_many :users, through: :book_club_memberships

  after_commit :refresh_live_panels, on: :update

  validates :name, presence: true

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

  def refresh_live_panels
    BookClubCurrentPickJob.perform_later(id) if saved_change_to_current_book_id? || saved_change_to_reading_deadline?
    BookClubLeaderboardJob.perform_later(id) if saved_change_to_current_book_id?
  end
end
