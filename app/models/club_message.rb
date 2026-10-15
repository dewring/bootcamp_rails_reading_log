class ClubMessage < ApplicationRecord
  belongs_to :book_club
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1_000 }

  def discussion_payload
    {
      id: id,
      body: body,
      author: { id: user_id, nickname: user.nickname },
      created_at: created_at.iso8601(6),
      updated_at: updated_at.iso8601(6)
    }
  end
end
