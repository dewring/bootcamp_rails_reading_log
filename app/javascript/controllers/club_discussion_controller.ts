import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

export interface DiscussionMessage {
  id: number
  body: string
  author: { id: number; nickname: string }
  created_at: string
  updated_at: string
}

interface DiscussionEvent {
  type: string
  message?: DiscussionMessage
  total_posts?: number
}

type DiscussionSubscription = { unsubscribe(): void }

export default class extends Controller {
  static targets = ["content", "status", "messages", "emptyState", "paginationSummary", "pagination", "olderPosts"]
  static values = { bookClubId: Number, page: Number, totalPosts: Number }

  declare readonly contentTarget: HTMLElement
  declare readonly statusTarget: HTMLElement
  declare readonly bookClubIdValue: number
  declare readonly pageValue: number
  declare totalPostsValue: number
  declare readonly messagesTarget: HTMLElement
  declare readonly emptyStateTarget: HTMLElement
  declare readonly paginationSummaryTarget: HTMLElement
  declare readonly paginationTarget: HTMLElement
  declare readonly olderPostsTarget: HTMLAnchorElement

  private discussionSubscription?: Promise<DiscussionSubscription | undefined>
  private receivedMessageIds = new Set<number>()

  connect() {
    this.receivedMessageIds = new Set(
      Array.from(this.messagesTarget.children, message => Number((message as HTMLElement).dataset.messageId))
    )
    const pendingSubscription: Promise<DiscussionSubscription | undefined> = cable.subscribeTo<DiscussionEvent>(
      { channel: "ClubDiscussionChannel", book_club_id: this.bookClubIdValue },
      {
        received: event => {
          if (this.discussionSubscription !== pendingSubscription) return

          if (event.type === "access.revoked") {
            this.endAccess()
          } else if (event.type === "message.created" && event.message) {
            this.displayCreatedMessage(event.message, event.total_posts)
          }
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
    this.receivedMessageIds.clear()
    this.unsubscribeFromDiscussion()
  }

  private endAccess() {
    this.contentTarget.replaceChildren()
    this.receivedMessageIds.clear()
    this.showStatus("Discussion access has ended. Sign in or reopen the club to continue.")
    this.unsubscribeFromDiscussion()
  }

  private showStatus(message: string) {
    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
  }

  private displayCreatedMessage(message: DiscussionMessage, totalPosts?: number) {
    if (!Number.isSafeInteger(message.id) || message.id <= 0) return
    if (this.receivedMessageIds.has(message.id)) return

    this.receivedMessageIds.add(message.id)
    if (totalPosts !== undefined) this.updatePaginationSummary(totalPosts)

    if (this.pageValue !== 1) {
      this.showStatus("New posts are available on the first page.")
      return
    }

    const article = this.buildMessageElement(message)
    const nextOlderPost = Array.from(this.messagesTarget.children).find(post => {
      return Number((post as HTMLElement).dataset.messageId) < message.id
    })
    if (nextOlderPost) {
      this.messagesTarget.insertBefore(article, nextOlderPost)
    } else {
      this.messagesTarget.append(article)
    }
    this.emptyStateTarget.hidden = true

    while (this.messagesTarget.children.length > 20) {
      this.messagesTarget.lastElementChild?.remove()
    }
  }

  private buildMessageElement(message: DiscussionMessage) {
    const article = document.createElement("article")
    article.id = `club_message_${message.id}`
    article.dataset.messageId = String(message.id)
    article.className = "club-discussion-message"

    const header = document.createElement("header")
    header.className = "club-discussion-message-meta"
    const author = document.createElement("strong")
    author.textContent = message.author.nickname
    const time = document.createElement("time")
    time.dateTime = message.created_at
    const createdAt = new Date(message.created_at)
    const dateText = createdAt.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" })
    const timeText = createdAt.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "UTC" })
    time.textContent = `${dateText} · ${timeText}`
    header.append(author, time)

    const body = document.createElement("p")
    body.className = "club-discussion-message-body"
    body.textContent = message.body
    article.append(header, body)
    return article
  }

  private updatePaginationSummary(totalPosts: number) {
    if (!Number.isSafeInteger(totalPosts) || totalPosts < 0) return

    this.totalPostsValue = Math.max(this.totalPostsValue, totalPosts)
    const pageCount = Math.max(1, Math.ceil(this.totalPostsValue / 20))
    const postLabel = this.totalPostsValue === 1 ? "post" : "posts"
    this.paginationSummaryTarget.textContent = `${this.totalPostsValue} ${postLabel} · Page ${this.pageValue} of ${pageCount}`
    this.olderPostsTarget.hidden = this.pageValue !== 1 || pageCount === 1 || this.paginationTarget.childElementCount > 0
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
