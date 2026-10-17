import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

interface DiscussionEvent {
  type: string
}

type DiscussionSubscription = { unsubscribe(): void }

export default class extends Controller {
  static targets = ["content", "status"]
  static values = { bookClubId: Number }

  declare readonly contentTarget: HTMLElement
  declare readonly statusTarget: HTMLElement
  declare readonly bookClubIdValue: number

  private discussionSubscription?: Promise<DiscussionSubscription | undefined>

  connect() {
    const pendingSubscription: Promise<DiscussionSubscription | undefined> = cable.subscribeTo<DiscussionEvent>(
      { channel: "ClubDiscussionChannel", book_club_id: this.bookClubIdValue },
      {
        received: event => {
          if (this.discussionSubscription !== pendingSubscription) return

          if (event.type === "access.revoked") this.endAccess()
        },
        rejected: () => {
          if (this.discussionSubscription === pendingSubscription) this.endAccess()
        },
        disconnected: ({ willAttemptReconnect }) => {
          if (this.discussionSubscription !== pendingSubscription) return

          if (!willAttemptReconnect) this.endAccess()
        }
      }
    ).catch(error => {
      console.error("Failed to subscribe to club discussion", error)
      if (this.discussionSubscription === pendingSubscription) {
        this.showStatus("Live updates could not connect. Refresh to try again.")
      }
      return undefined
    })

    this.discussionSubscription = pendingSubscription
  }

  disconnect() {
    this.unsubscribeFromDiscussion()
  }

  beforeCache() {
    this.contentTarget.replaceChildren()
    this.unsubscribeFromDiscussion()
  }

  private endAccess() {
    this.contentTarget.replaceChildren()
    this.showStatus("Discussion access has ended. Sign in or reopen the club to continue.")
    this.unsubscribeFromDiscussion()
  }

  private showStatus(message: string) {
    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
  }

  private unsubscribeFromDiscussion() {
    const pendingSubscription = this.discussionSubscription
    this.discussionSubscription = undefined

    pendingSubscription?.then(subscription => {
      subscription?.unsubscribe()
    }).catch(error => {
      console.error("Failed to unsubscribe from club discussion", error)
    })
  }
}
