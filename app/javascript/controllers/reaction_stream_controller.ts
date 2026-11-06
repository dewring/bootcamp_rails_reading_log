import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { renderStreamMessage } from "@hotwired/turbo"

type Subscription = { unsubscribe(): void }
interface PanelRecoveryAttempt {
  request: AbortController
  events: string[]
  timeout?: ReturnType<typeof setTimeout>
}

export default class extends Controller {
  static values = { signedStreamName: String, refreshUrl: String }
  declare readonly signedStreamNameValue: string
  declare readonly refreshUrlValue: string

  private subscription?: Promise<Subscription | undefined>
  private recovery?: PanelRecoveryAttempt

  connect() {
    const pending: Promise<Subscription | undefined> = cable.subscribeTo<string>(
      { channel: "Turbo::StreamsChannel", signed_stream_name: this.signedStreamNameValue },
      {
        received: message => {
          if (this.subscription !== pending) return

          if (this.recovery) this.recovery.events.push(message)
          else renderStreamMessage(message)
        },
        connected: () => {
          if (this.subscription !== pending) return

          // Cable delivers live counts. Read once after connection to recover
          // missed updates and private selections; this is not periodic polling.
          // Buffer incoming counts until the snapshot has rendered.
          this.recoverPanelsAfterConnection().catch(error => console.error("Failed to recover book reactions", error))
        },
        disconnected: () => {
          if (this.subscription === pending) this.cancelRecovery()
        },
        rejected: () => {
          if (this.subscription === pending) this.showStatus("Live reactions could not connect. Refresh the page to try again.")
        }
      }
    ).catch(error => {
      console.error("Failed to subscribe to book reactions", error)
      if (this.subscription === pending) this.showStatus("Live reactions could not connect. Refresh the page to try again.")
      return undefined
    })
    this.subscription = pending
  }

  disconnect() {
    this.cancelRecovery()
    const pending = this.subscription
    this.subscription = undefined
    pending?.then(subscription => subscription?.unsubscribe())
      .catch(error => console.error("Failed to unsubscribe from book reactions", error))
  }

  frameMissing(event: CustomEvent<{ response: Response }>) {
    const frame = event.target as HTMLElement
    if (!frame.matches("turbo-frame.reaction-panel")) return

    event.preventDefault()
    if (event.detail.response.status === 404) frame.remove()
    else this.showStatus(event.detail.response.status === 429
      ? "Too many reaction changes. Wait a minute before trying again."
      : "Reaction could not be confirmed. Refresh the page to check your selection.")
  }

  frameError(event: Event) {
    if ((event.target as HTMLElement).closest("turbo-frame.reaction-panel")) {
      this.showStatus("Reaction could not be confirmed. Refresh the page to check your selection.")
    }
  }

  private async recoverPanelsAfterConnection() {
    this.cancelRecovery()
    const recovery: PanelRecoveryAttempt = { request: new AbortController(), events: [] }
    this.recovery = recovery
    recovery.timeout = setTimeout(() => recovery.request.abort(), 10_000)
    try {
      const response = await fetch(this.refreshUrlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin",
        cache: "no-store", signal: recovery.request.signal
      })
      if (!response.ok) throw new Error(`Book reaction recovery returned ${response.status}`)

      const html = await response.text()
      if (this.recovery !== recovery || !this.element.isConnected) return

      renderStreamMessage(html)
      this.showStatus("")
    } catch (error) {
      if (this.recovery === recovery) {
        console.error("Failed to recover book reactions", error)
        this.showStatus("Reactions could not refresh. Your draft is still here. Refresh the page to try again.")
      }
    } finally {
      clearTimeout(recovery.timeout)
      if (this.recovery === recovery) {
        for (const message of recovery.events) renderStreamMessage(message)
        this.recovery = undefined
      }
    }
  }

  private cancelRecovery() {
    const recovery = this.recovery
    this.recovery = undefined
    clearTimeout(recovery?.timeout)
    recovery?.request.abort()
    if (this.element.isConnected) {
      for (const message of recovery?.events ?? []) renderStreamMessage(message)
    }
  }

  private showStatus(message: string) {
    const status = this.element.querySelector<HTMLElement>("[data-reaction-stream-status]")
    if (status) {
      status.textContent = message
      status.hidden = message.length === 0
    }
  }
}
