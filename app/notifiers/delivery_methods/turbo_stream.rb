class DeliveryMethods::TurboStream < ApplicationDeliveryMethod
  def deliver
    Turbo::StreamsChannel.broadcast_replace_to(
      recipient,
      :notifications,
      target: "notifications_panel",
      partial: "notifications/panel",
      locals: NotificationsPanel.new(recipient).locals
    )
  end
end
