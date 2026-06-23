class Api::ReadingSessionsController < ApplicationController
  before_action :authenticate_user!
  rescue_from Pundit::NotAuthorizedError, with: :not_authorized

  def index
    sessions = ReadingSessionFinder.new(current_user, params).find
    authorize sessions, policy_class: ReadingSessionPolicy
    render json: sessions
  end
  def show
    @reading_session = ReadingSession.find(params[:id])
    authorize @reading_session
    render json: @reading_session
  end
  def create
    book = Book.find(params[:book_id])
    @reading_session = ReadingSessionRecorder.new(book, current_user, reading_session_params).record
    authorize @reading_session
    if @reading_session.persisted?
      render json: @reading_session, status: :created
    else
      render json: @reading_session, status: :unprocessable_entity
    end
  end

  private
  def not_authorized
    render json: { error: "Forbidden" }, status: :forbidden
  end
  def reading_session_params
    params.require(:reading_session).permit(:read_on, :pages_read, :notes)
  end
end
