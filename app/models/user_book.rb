class UserBook < ApplicationRecord
  belongs_to :user
  belongs_to :book

  STATUSES = [ "want_to_read", "reading", "finished" ].freeze

  include RecalculateChallengeProgress

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :book_id, message: "already has this book in their log" }

  validate :reading_sessions_cannot_be_saved_as_want_to_read

  private

  def reading_sessions_cannot_be_saved_as_want_to_read
    return unless status == "want_to_read" && user_id.present? && book_id.present?
    return unless ReadingSession.exists?(user_id: user_id, book_id: book_id)

    errors.add(:status, "cannot be want to read after reading has started")
  end
end
