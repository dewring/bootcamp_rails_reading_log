import NavDropdownController from "./nav_dropdown_controller"
import { renderStreamMessage } from "@hotwired/turbo"
import { cable } from "@hotwired/turbo-rails"

export default class extends NavDropdownController {
  private notificationSubscription?: { unsubscribe: () => void }
  private subscriptionGeneration = 0

  connect() {
    this.subscribeToNotifications(++this.subscriptionGeneration).catch(error => {
      console.error("Failed to subscribe to notifications", error)
    })
  }

  disconnect() {
    super.disconnect()
    this.subscriptionGeneration += 1
    this.notificationSubscription?.unsubscribe()
    this.notificationSubscription = undefined
  }

  private async subscribeToNotifications(generation: number) {
    const subscription = await cable.subscribeTo("Noticed::NotificationChannel", {
      received: (message: string) => renderStreamMessage(message)
    })

    if (generation !== this.subscriptionGeneration) {
      subscription.unsubscribe()
      return
    }

    this.notificationSubscription = subscription
  }
}
