class ClubMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book_club

  def index
    authorize @book_club, :discuss?
    messages = policy_scope(@book_club.club_messages)
      .includes(:user)
      .order(id: :desc)

    response.headers["Cache-Control"] = "no-store"

    respond_to do |format|
      format.json do
        render json: { messages: messages.limit(20).map(&:discussion_payload) }
      end
      format.html do
        @pagy, @messages = pagy(:offset, messages, limit: 20)
      end
    end
  end

  def create
    message = @book_club.club_messages.build(message_params)
    message.user = current_user
    authorize message

    if message.save
      render json: { message: message.discussion_payload }, status: :created
    else
      render json: { errors: message.errors.to_hash }, status: :unprocessable_entity
    end
  end

  private

  def set_book_club
    @book_club = BookClub.find(params[:book_club_id])
  end

  def message_params
    params.require(:club_message).permit(:body)
  end
end
