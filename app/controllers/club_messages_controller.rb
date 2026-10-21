class ClubMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book_club

  def index
    authorize @book_club, :discuss?
    messages = policy_scope(@book_club.club_messages)
      .visible_posts
      .with_reply_counts
      .includes(:user)
      .order(id: :desc)

    response.headers["Cache-Control"] = "no-store"

    respond_to do |format|
      format.json do
        render json: { messages: messages.limit(20).map(&:discussion_payload) }
      end
      format.html do
        @book_club.preload_covers
        @pagy, @messages = pagy(:offset, messages, limit: 20)
      end
    end
  end

  private

  def set_book_club
    @book_club = BookClub.find(params[:book_club_id])
  end
end
