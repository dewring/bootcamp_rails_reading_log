class ReadingSessionFinder
  def initialize(user, params)
    @user = user
    @params = params
  end

  def find
    sessions = ReadingSessionPolicy::Scope.new(@user, ReadingSession.all).resolve
    sessions = sessions.where(book_id: @params[:book_id]) if @params[:book_id].present?
    sessions = sessions.where(read_on: @params[:read_on]) if @params[:read_on].present?
    if @params[:q].present?
      sessions = sessions.joins(:book)
                         .where("books.title LIKE :q OR books.author LIKE :q",
                                 q: "%#{@params[:q]}%")
    end
    sessions
  end
end
