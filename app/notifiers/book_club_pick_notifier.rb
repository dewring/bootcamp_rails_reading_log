class BookClubPickNotifier < ApplicationNotifier
  deliver_by :action_cable do |config|
    config.message = :render_notification_panel
  end

  required_params :book_club_name, :book_title

  notification_methods do
    def message
      "#{params[:book_club_name]} chose #{params[:book_title]}."
    end
  end

  def render_notification_panel(notification)
    ApplicationController.render(
      template: "notifications/update",
      formats: [ :turbo_stream ],
      locals: { notification: notification }
    )
  end
end
