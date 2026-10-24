class ClubMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book_club

  def index
    authorize @book_club, :discuss?
    messages = policy_scope(@book_club.club_messages)
      .visible_posts
      .with_reply_counts
      .includes(user: { avatar_attachment: :blob })
      .order(id: :desc)

    response.headers["Cache-Control"] = "no-store"
    @pagy, @messages = pagy(:offset, messages, limit: 10)

    respond_to do |format|
      format.json do
        render json: {
          messages: @messages.map(&:discussion_payload),
          pagination_html: render_to_string(partial: "club_messages/pagination", formats: [ :html ])
        }
      end
      format.html do
        @book_club.preload_covers
      end
    end
  end

  private

  def set_book_club
    @book_club = BookClub.find(params[:book_club_id])
  end
end
