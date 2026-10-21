class ClubMessage < ApplicationRecord
  belongs_to :book_club
  belongs_to :user
  belongs_to :parent, class_name: "ClubMessage", optional: true, inverse_of: :replies
  has_many :replies, class_name: "ClubMessage", foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy

  validates :body, presence: true, unless: :deleted?
  validates :body, length: { maximum: 1_000 }
  validate :deleted_post_state_is_valid
  validate :reply_parent_is_valid

  scope :top_level, -> { where(parent_id: nil) }

  after_create_commit :broadcast_created_message
  after_update_commit :broadcast_updated_message, if: -> { saved_change_to_body? || saved_change_to_deleted_at? }

  def deleted?
    deleted_at.present?
  end

  def remove_from_discussion!
    with_lock do
      if parent_id.present?
        remove_reply_from_discussion!
      else
        update!(body: "", deleted_at: Time.current) unless deleted?
        discussion_payload
      end
    end
  end

  def discussion_payload
    {
      id: id,
      parent_id: parent_id,
      body: body,
      deleted: deleted?,
      author: { id: user_id, nickname: user.nickname },
      created_at: created_at.iso8601(6),
      updated_at: updated_at.iso8601(6)
    }
  end

  private

  def deleted_post_state_is_valid
    return unless deleted?

    errors.add(:deleted_at, "is only allowed on top-level posts") if parent_id.present?
    errors.add(:body, "must be empty for a deleted post") unless body == ""
  end

  def remove_reply_from_discussion!
    club = book_club
    payload = discussion_payload.merge(body: "", deleted: true, updated_at: Time.current.iso8601(6))
    destroy!
    ActiveRecord.after_all_transactions_commit do
      ClubDiscussionChannel.broadcast_to(club, {
        type: "reply.deleted", message: payload, total_posts: club.club_messages.top_level.count
      })
    end
    payload
  end

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

    if (new_record? || will_save_change_to_parent_id?) && parent.deleted?
      errors.add(:parent, "cannot be a deleted post")
    end
    errors.add(:parent, "must belong to the same book club") if parent.book_club != book_club
    errors.add(:parent, "would create nested replies") if parent.parent.present? || replies.exists?
  end

  def broadcast_created_message
    broadcast_discussion_change("created")
  end

  def broadcast_updated_message
    broadcast_discussion_change(deleted? ? "deleted" : "updated")
  end

  def broadcast_discussion_change(change)
    event_prefix = if parent_id.present?
      "reply"
    else
      "message"
    end

    ClubDiscussionChannel.broadcast_to(
      book_club,
      { type: "#{event_prefix}.#{change}", message: discussion_payload, total_posts: book_club.club_messages.top_level.count }
    )
  end
end
