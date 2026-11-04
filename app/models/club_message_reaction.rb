class ClubMessageReaction < ApplicationRecord
  include ReactionBehavior

  belongs_to :club_message

  validates :user_id, uniqueness: { scope: :club_message_id }
  validate :message_is_not_deleted

  private

  def message_is_not_deleted
    errors.add(:club_message, "has been deleted") if club_message&.deleted?
  end
end
