class BookClubReplyNotifier < ApplicationNotifier
  required_params :book_club_name, :reply_author_name

  notification_methods do
    def message
      "#{params[:reply_author_name]} replied to your discussion in #{params[:book_club_name]}."
    end

    def url
      book_club_club_messages_path(record) if record.present?
    end
  end
end
