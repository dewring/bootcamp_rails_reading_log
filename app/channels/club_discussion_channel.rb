class ClubDiscussionChannel < ApplicationCable::Channel
  def subscribed
    @book_club = BookClub.find_by(id: params[:book_club_id])

    if discussion_allowed?
      stream_for @book_club, coder: ActiveSupport::JSON do |event|
        transmit_discussion_event(event)
      end
    else
      reject
    end
  end

  private

  def discussion_allowed?
    return false unless @book_club && current_user

    user = User.find_by(id: current_user.id)
    BookClub.exists?(@book_club.id) && BookClubPolicy.new(user, @book_club).discuss?
  end

  def transmit_discussion_event(event)
    return if @access_revoked

    if discussion_allowed?
      transmit event
    else
      @access_revoked = true
      stop_all_streams
      transmit({ type: "access.revoked" })
    end
  end
end
