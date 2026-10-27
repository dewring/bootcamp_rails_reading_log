import type { DiscussionEvent, DiscussionHistory, DiscussionSubscription } from "./types"

interface RecoveryContext {
  connected: boolean
  subscription?: Promise<DiscussionSubscription | undefined>
  url: string
  page: number
}

interface RecoveryOptions {
  root: HTMLElement
  context(): RecoveryContext
  targets(): { status?: HTMLElement; retry?: HTMLButtonElement }
  beforeRead(): void
  applyHistory(history: DiscussionHistory, events: DiscussionEvent[]): void
  replayEvents(events: DiscussionEvent[]): void
  endAccess(): void
}

interface RecoveryAttempt {
  request: AbortController
  subscription: Promise<DiscussionSubscription | undefined>
  events: DiscussionEvent[]
  buffering: boolean
  timeout?: ReturnType<typeof setTimeout>
}

type ConnectionState = "connecting" | "recovering" | "live" | "offline" | "failed"

export function discussionAccessDenied(response: Response) {
  return response.status === 401 || response.status === 403 ||
    (response.redirected && new URL(response.url, window.location.origin).pathname === "/users/sign_in")
}

export default class DiscussionRecovery {
  private attempt?: RecoveryAttempt

  constructor(private options: RecoveryOptions) {
    this.showState("connecting")
  }

  get isRecovering() {
    return this.attempt !== undefined
  }

  bufferEvent(event: DiscussionEvent): boolean {
    if (!this.attempt?.buffering) return false

    this.attempt.events.push(event)
    return true
  }

  async recoverPage(): Promise<DiscussionHistory | undefined> {
    const context = this.options.context()
    if (!context.connected || !context.subscription || this.attempt) return
    if (!context.url) {
      this.showState("failed")
      return
    }

    this.options.beforeRead()
    const attempt: RecoveryAttempt = {
      request: new AbortController(),
      subscription: context.subscription,
      events: [],
      buffering: true
    }
    this.attempt = attempt
    this.showState("recovering")
    // A stalled read must become retryable rather than remain Recovering forever.
    attempt.timeout = setTimeout(() => attempt.request.abort(), 10_000)

    try {
      const url = new URL(context.url, window.location.origin)
      url.searchParams.set("page", String(context.page))
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        signal: attempt.request.signal,
        cache: "no-store"
      })
      if (!this.ownsAttempt(attempt)) return
      if (discussionAccessDenied(response)) {
        this.options.endAccess()
        return
      }
      if (!response.ok) throw new Error(`Discussion recovery returned ${response.status}`)

      const history: DiscussionHistory = await response.json()
      if (!this.ownsAttempt(attempt)) return
      if (attempt.request.signal.aborted) throw new Error("Discussion recovery timed out")
      this.validateHistory(history)
      attempt.buffering = false
      this.options.applyHistory(history, attempt.events)
      this.attempt = undefined
      this.showState("live")
      return history
    } catch (error) {
      if (!this.ownsAttempt(attempt)) return

      console.error("Failed to recover club discussion", error)
      this.cancelRecovery(true)
      this.showState("failed")
    } finally {
      clearTimeout(attempt.timeout)
    }
  }

  connectionLost() {
    this.cancelRecovery(true)
    this.showState("offline")
  }

  disconnect() {
    this.cancelRecovery(false)
    this.showState("offline")
  }

  private cancelRecovery(mergeEvents: boolean) {
    const attempt = this.attempt
    this.attempt = undefined
    if (!attempt) return

    clearTimeout(attempt.timeout)
    attempt.request.abort()
    if (mergeEvents) this.options.replayEvents(attempt.events)
    attempt.events.length = 0
  }

  private ownsAttempt(attempt: RecoveryAttempt) {
    return this.attempt === attempt && this.options.context().subscription === attempt.subscription && this.options.root.isConnected
  }

  private validateHistory(history: DiscussionHistory) {
    if (!Array.isArray(history.messages) || !Number.isSafeInteger(history.total_posts) || history.total_posts < 0 ||
      typeof history.pagination_html !== "string" || history.messages.some(message =>
        !Number.isSafeInteger(message.id) || message.id <= 0 || message.parent_id !== null ||
        typeof message.body !== "string" || !message.author || typeof message.author.nickname !== "string" ||
        !Number.isSafeInteger(message.author.id) || !Number.isFinite(Date.parse(message.created_at)) ||
        !Number.isFinite(Date.parse(message.updated_at)))) {
      throw new Error("Discussion recovery returned an invalid page")
    }
  }

  private showState(state: ConnectionState) {
    const labels: Record<ConnectionState, string> = {
      connecting: "Connecting…",
      recovering: "Recovering discussion…",
      live: "Discussion live",
      offline: "Offline · discussion updates paused.",
      failed: "Recovery failed · your draft is still here. Retry to refresh the discussion."
    }
    this.options.root.dataset.connectionState = state
    const targets = this.options.targets()
    if (targets.status) targets.status.textContent = labels[state]
    if (targets.retry) targets.retry.hidden = state !== "failed"
  }
}
