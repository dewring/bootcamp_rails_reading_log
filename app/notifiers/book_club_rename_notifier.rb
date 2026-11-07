class BookClubRenameNotifier < ApplicationNotifier
  required_params :previous_name, :book_club_name

  notification_methods do
    def message
      "#{params[:previous_name]} was renamed to #{params[:book_club_name]}."
    end
  end
end
