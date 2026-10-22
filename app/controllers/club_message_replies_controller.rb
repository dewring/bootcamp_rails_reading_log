class ClubMessageRepliesController < ApplicationController
  before_action :authenticate_user!

  def index
    book_club = BookClub.find(params[:book_club_id])
    authorize book_club, :discuss?
    parent = policy_scope(book_club.club_messages).top_level.find(params[:club_message_id])
    replies = parent.replies.includes(user: { avatar_attachment: :blob }).order(id: :asc)
    pagy, messages = pagy(:offset, replies, limit: 20)

    response.headers["Cache-Control"] = "no-store"
    render json: {
      replies: messages.map(&:discussion_payload),
      pagination: { page: pagy.page, next_page: pagy.next, last_page: pagy.last, total_count: pagy.count }
    }
  end
end
