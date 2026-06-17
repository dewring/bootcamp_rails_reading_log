class ReadingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: [ :new, :create ]   # load @book
  before_action :set_reading_session, only: [ :update, :edit, :destroy ]   # load @reading_session

  def index
    @reading_sessions = if current_user.admin?
      ReadingSession.all
    else
      current_user.reading_sessions
    end
    respond_to do |format|
      format.json { render json: @reading_sessions }
    end
  end
  def new
    @reading_session = @book.reading_sessions.build
  end

  def create
    @reading_session = @book.reading_sessions.build(reading_session_params)
    @reading_session.user = current_user
    if @reading_session.save
      redirect_to book_path(@book), notice: "Reading session logged!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # nothing needed!
  end

  def update
    if @reading_session.update(reading_session_params)
      redirect_to book_path(@reading_session.book), notice: "Reading session updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @reading_session.destroy
    redirect_to book_path(@reading_session.book), notice: "Reading session deleted."
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
