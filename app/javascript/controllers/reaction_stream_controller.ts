import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { renderStreamMessage } from "@hotwired/turbo"

type Subscription = { unsubscribe(): void }
interface RefreshAttempt {
  request: AbortController
  events: string[]
  timeout?: ReturnType<typeof setTimeout>
}

export default class extends Controller {
  static values = { signedStreamName: String, refreshUrl: String }
  declare readonly signedStreamNameValue: string
  declare readonly refreshUrlValue: string

  private subscription?: Promise<Subscription | undefined>
  private refresh?: RefreshAttempt

  connect() {
    const pending: Promise<Subscription | undefined> = cable.subscribeTo<string>(
      { channel: "Turbo::StreamsChannel", signed_stream_name: this.signedStreamNameValue },
      {
        received: message => {
          if (this.subscription !== pending) return

          if (this.refresh) this.refresh.events.push(message)
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
          if (this.subscription === pending) this.cancelRefresh()
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
    this.cancelRefresh()
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
    this.cancelRefresh()
    const refresh: RefreshAttempt = { request: new AbortController(), events: [] }
    this.refresh = refresh
    refresh.timeout = setTimeout(() => refresh.request.abort(), 10_000)
    try {
      const response = await fetch(this.refreshUrlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin",
        cache: "no-store", signal: refresh.request.signal
      })
      if (!response.ok) throw new Error(`Book reaction refresh returned ${response.status}`)

      const html = await response.text()
      if (this.refresh !== refresh || !this.element.isConnected) return

      renderStreamMessage(html)
      this.showStatus("")
    } catch (error) {
      if (this.refresh === refresh) {
        console.error("Failed to refresh book reactions", error)
        this.showStatus("Reactions could not refresh. Your draft is still here. Refresh the page to try again.")
      }
    } finally {
      clearTimeout(refresh.timeout)
      if (this.refresh === refresh) {
        for (const message of refresh.events) renderStreamMessage(message)
        this.refresh = undefined
      }
    }
  }

  private cancelRefresh() {
    const refresh = this.refresh
    this.refresh = undefined
    clearTimeout(refresh?.timeout)
    refresh?.request.abort()
    if (this.element.isConnected) {
      for (const message of refresh?.events ?? []) renderStreamMessage(message)
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
