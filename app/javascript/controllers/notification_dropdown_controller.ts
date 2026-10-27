import NavDropdownController from "./nav_dropdown_controller"
import { renderStreamMessage } from "@hotwired/turbo"
import { cable } from "@hotwired/turbo-rails"

export default class extends NavDropdownController {
  private notificationSubscription?: Promise<{ unsubscribe: () => void } | undefined>

  menuTargetConnected(menu: HTMLElement) {
    menu.hidden = !this.openValue
  }

  triggerTargetConnected(trigger: HTMLButtonElement) {
    trigger.setAttribute("aria-expanded", String(this.openValue))
  }

  connect() {
    this.notificationSubscription = cable.subscribeTo("Noticed::NotificationChannel", {
      received: (message: string) => renderStreamMessage(message)
    }).catch(error => {
      console.error("Failed to subscribe to notifications", error)
      return undefined
    })
  }

  disconnect() {
    super.disconnect()
    const pendingSubscription = this.notificationSubscription
    this.notificationSubscription = undefined
    pendingSubscription?.then(subscription => {
      subscription?.unsubscribe()
    }).catch(error => {
      console.error("Failed to unsubscribe from notifications", error)
    })
  }
}
