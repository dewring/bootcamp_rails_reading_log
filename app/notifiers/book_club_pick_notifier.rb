class BookClubPickNotifier < ApplicationNotifier
  deliver_by :turbo_stream, class: "DeliveryMethods::TurboStream"

  required_params :book_club_name, :book_title

  notification_methods do
    def message
      "#{params[:book_club_name]} chose #{params[:book_title]}."
    end
  end
end
