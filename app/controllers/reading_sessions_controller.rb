class ReadingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: [ :new, :create, :show, :finished, :destroy_finished ]   # load @book
  before_action :set_reading_session, only: [ :update, :edit, :destroy ]   # load @reading_session

  def index
    authorize ReadingSession
    @reading_sessions = policy_scope(ReadingSession)
    @finished_books = current_user.user_books
      .where(status: "finished")
      .includes(book: { cover_image_attachment: :blob })
      .order(updated_at: :desc)
      .to_a
    @badges = Badge.order(:id)
    @earned_badge_ids = current_user.user_badges
      .where(badge_id: @badges.select(:id))
      .pluck(:badge_id)

    respond_to do |format|
      format.html
      format.json { render json: @reading_sessions }
    end
  end
  def new
    @reading_session = @book.reading_sessions.build(read_on: Date.today)
    authorize @reading_session
  end

  def show
    @reading_session = @book.reading_sessions.build(user: current_user, read_on: Date.current)
    @reading_sessions = policy_scope(@book.reading_sessions).order(read_on: :desc, created_at: :desc)
    authorize @reading_session, :show?
  end

  def finished
    @finished_user_book = current_user.user_books.find_by(book: @book, status: "finished")
    return redirect_to book_reading_journal_path(@book) unless @finished_user_book

    @finished_on = @finished_user_book.updated_at.to_date
    @reading_sessions = policy_scope(@book.reading_sessions).order(read_on: :desc, created_at: :desc)
    authorize @book.reading_sessions.build(user: current_user), :show?
  end

  def destroy_finished
    user_book = current_user.user_books.find_by!(book: @book, status: "finished")
    authorize user_book, :destroy?
    FinishedBookResetter.new(user: current_user, book: @book).reset_finished_book

    redirect_to book_path(@book), notice: "Finished reading history deleted."
  end

  def create
    authorize @book.reading_sessions.build(user: current_user), :create?
    @reading_session = ReadingSessionRecorder.new(@book, current_user, reading_session_params).record
    if @reading_session.persisted?
      redirect_to reading_session_destination, notice: "Reading session logged!"
    else
      if reading_journal_requested?
        @reading_sessions = policy_scope(@book.reading_sessions).order(read_on: :desc, created_at: :desc)
        render :show, status: :unprocessable_entity
      else
        render :new, status: :unprocessable_entity
      end
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

  def reading_journal_requested?
    params[:return_to] == "reading_journal"
  end

  def reading_session_destination
    reading_journal_requested? ? book_reading_journal_path(@book) : dashboard_path
  end
end
