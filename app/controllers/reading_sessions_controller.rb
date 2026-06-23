class ReadingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: [ :new, :create ]   # load @book
  before_action :set_reading_session, only: [ :update, :edit, :destroy ]   # load @reading_session

  def index
    @reading_sessions = policy_scope(ReadingSession)
    respond_to do |format|
      format.json { render json: @reading_sessions }
    end
  end
  def new
    @reading_session = @book.reading_sessions.build(read_on: Date.today)
    authorize @reading_session
  end

  def create
    @reading_session = ReadingSessionRecorder.new(current_user, @book, reading_session_params).record
    authorize @reading_session
    if @reading_session.persisted?
      redirect_to book_path(@book), notice: "Reading session logged!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @reading_session
  end

  def update
    authorize @reading_session
    if @reading_session.update(reading_session_params)
      redirect_to dashboard_path, notice: "Reading session updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @reading_session
    @reading_session.destroy
    redirect_to dashboard_path, notice: "Reading session deleted."
  end

  private
  def set_book
    @book = Book.find(params[:book_id])
  end

  def set_reading_session
    @reading_session = ReadingSession.find(params[:id])
  end
  def reading_session_params
    params.require(:reading_session).permit(:read_on, :pages_read, :notes)
  end
end
