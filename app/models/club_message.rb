class ClubMessage < ApplicationRecord
  belongs_to :book_club
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1_000 }

  after_create_commit :broadcast_created_message

  def discussion_payload
    {
      id: id,
      body: body,
      author: { id: user_id, nickname: user.nickname },
      created_at: created_at.iso8601(6),
      updated_at: updated_at.iso8601(6)
    }
  end

  private

  def broadcast_created_message
    ClubDiscussionChannel.broadcast_to(
      book_club,
      { type: "message.created", message: discussion_payload, total_posts: book_club.club_messages.count }
    )
  end
end
