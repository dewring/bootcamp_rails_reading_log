class ApplicationNotifier < Noticed::Event
  deliver_by :action_cable do |config|
    config.message = :render_notification_panel
  end

  notification_methods do
    def url
      book_club_path(record) if record.present?
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
