class BookClubDeadlineNotifier < ApplicationNotifier
  required_params :book_club_name, :reading_deadline

  notification_methods do
    def message
      if params[:reading_deadline].present?
        "#{params[:book_club_name]} set the reading deadline to #{Date.iso8601(params[:reading_deadline]).to_fs(:long)}."
      else
        "#{params[:book_club_name]} cleared its reading deadline."
      end
    end
  end
end
