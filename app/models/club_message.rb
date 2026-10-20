class ClubMessage < ApplicationRecord
  belongs_to :book_club
  belongs_to :user
  belongs_to :parent, class_name: "ClubMessage", optional: true, inverse_of: :replies
  has_many :replies, class_name: "ClubMessage", foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy

  validates :body, presence: true, length: { maximum: 1_000 }
  validate :reply_parent_is_valid

  scope :top_level, -> { where(parent_id: nil) }

  after_create_commit :broadcast_created_message

  def discussion_payload
    {
      id: id,
      parent_id: parent_id,
      body: body,
      author: { id: user_id, nickname: user.nickname },
      created_at: created_at.iso8601(6),
      updated_at: updated_at.iso8601(6)
    }
  end

  private

  def reply_parent_is_valid
    return if parent_id.nil? && parent.nil?

    if parent.nil?
      errors.add(:parent, "must exist")
      return
    end
    if parent == self
      errors.add(:parent, "cannot be the message itself")
      return
    end

    errors.add(:parent, "must belong to the same book club") if parent.book_club != book_club
    errors.add(:parent, "would create nested replies") if parent.parent.present? || replies.exists?
  end

  def broadcast_created_message
    event_type = if parent_id.present?
      "reply.created"
    else
      "message.created"
    end

    ClubDiscussionChannel.broadcast_to(
      book_club,
      { type: event_type, message: discussion_payload, total_posts: book_club.club_messages.top_level.count }
    )
  end
end
