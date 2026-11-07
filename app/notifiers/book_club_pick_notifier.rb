class BookClubPickNotifier < ApplicationNotifier
  required_params :book_club_name, :book_title

  notification_methods do
    def message
      if params[:book_title].present?
        "#{params[:book_club_name]} chose #{params[:book_title]}."
      else
        "#{params[:book_club_name]} cleared its current pick."
      end
    end
  end
end
