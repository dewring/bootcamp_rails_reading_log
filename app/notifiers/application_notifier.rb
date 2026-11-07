class ApplicationNotifier < Noticed::Event
  deliver_by :action_cable do |config|
    config.message = :render_notification_panel
  end

  def render_notification_panel(notification)
    ApplicationController.render(
      template: "notifications/update",
      formats: [ :turbo_stream ],
      locals: { notification: notification }
    )
  end
end
