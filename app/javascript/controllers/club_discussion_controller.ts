import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

export interface DiscussionMessage {
  id: number
  parent_id: number | null
  body: string
  author: { id: number; nickname: string }
  created_at: string
  updated_at: string
}

export interface DiscussionEvent {
  type: string
  message?: DiscussionMessage
  total_posts?: number
  request_id?: string
  errors?: { body?: string[] }
  error?: string
}

type DiscussionSubscription = {
  unsubscribe(): void
  perform(action: string, data: { request_id: string; body: string; parent_id?: number }): boolean
}

export default class extends Controller {
  static targets = ["content", "status", "messages", "emptyState", "paginationSummary", "pagination", "olderPosts", "body", "submit", "composerStatus", "replyControls"]
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
  declare readonly hasBodyTarget: boolean
  declare readonly hasSubmitTarget: boolean
  declare readonly hasComposerStatusTarget: boolean
  declare readonly bodyTarget: HTMLTextAreaElement
  declare readonly submitTarget: HTMLButtonElement
  declare readonly composerStatusTarget: HTMLElement

  declare readonly replyControlsTarget: HTMLTemplateElement
  declare readonly hasReplyControlsTarget: boolean

  private discussionSubscription?: Promise<DiscussionSubscription | undefined>
  private receivedMessageIds = new Set<number>()
  private posting = false
  private cableConnected = false
  private pendingPostId?: string
  private postTimeout?: ReturnType<typeof setTimeout>

  connect() {
    this.receivedMessageIds = new Set(
      Array.from(this.messagesTarget.children, message => Number((message as HTMLElement).dataset.messageId))
    )
    const pendingSubscription: Promise<DiscussionSubscription | undefined> = cable.subscribeTo<DiscussionEvent>(
      { channel: "ClubDiscussionChannel", book_club_id: this.bookClubIdValue },
      {
        connected: () => {
          if (this.discussionSubscription !== pendingSubscription) return

          this.cableConnected = true
          if (this.hasSubmitTarget) this.submitTarget.disabled = this.posting
        },
        received: event => {
          if (this.discussionSubscription !== pendingSubscription) return

          if (event.type === "access.revoked") {
            this.endAccess()
          } else if (event.type === "message.created" && event.message) {
            this.displayCreatedMessage(event.message, event.total_posts)
          } else if (event.type === "reply.created" || event.type === "reply.saved" || event.type === "reply.rejected") {
            this.dispatch("reply", { detail: event })
          } else if (event.type === "post.saved" || event.type === "post.rejected") {
            this.receivePostResult(event)
          }
        },
        rejected: () => {
          if (this.discussionSubscription === pendingSubscription) this.endAccess()
        },
        disconnected: ({ willAttemptReconnect }) => {
          if (this.discussionSubscription !== pendingSubscription) return

          this.cableConnected = false
          this.dispatch("connection-ended")
          this.interruptPosting()
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
    this.dispatch("connection-ended")
    this.cableConnected = false
    this.interruptPosting()
    this.unsubscribeFromDiscussion()
  }

  beforeCache() {
    this.cableConnected = false
    this.finishPosting()
    this.contentTarget.replaceChildren()
    this.receivedMessageIds.clear()
    this.unsubscribeFromDiscussion()
  }

  async postMessage(event: SubmitEvent) {
    event.preventDefault()
    if (this.posting) return
    if (!this.cableConnected) {
      this.composerStatusTarget.textContent = "Live connection is not ready. Your draft is still here."
      return
    }

    const pendingSubscription = this.discussionSubscription
    const requestId = crypto.randomUUID()
    this.pendingPostId = requestId
    this.setPosting(true)
    this.composerStatusTarget.textContent = "Posting…"

    try {
      const subscription = await pendingSubscription
      if (this.discussionSubscription !== pendingSubscription || this.pendingPostId !== requestId) return

      const sent = subscription?.perform("post_message", { request_id: requestId, body: this.bodyTarget.value })
      if (!sent) {
        this.interruptPosting()
        return
      }

      // No automatic retry: a missing acknowledgement does not prove the save failed.
      this.postTimeout = setTimeout(() => this.interruptPosting(), 20_000)
    } catch (error) {
      console.error("Failed to send discussion post", error)
      if (this.pendingPostId === requestId) this.interruptPosting()
    }
  }

  async sendReply(requestId: string, parentId: number, body: string, composer: Element): Promise<boolean> {
    if (!this.cableConnected) return false

    const pendingSubscription = this.discussionSubscription
    const subscription = await pendingSubscription
    if (this.discussionSubscription !== pendingSubscription || !this.cableConnected) return false

    if (!composer.isConnected || !this.element.contains(composer)) return false

    return subscription?.perform("post_reply", { request_id: requestId, parent_id: parentId, body }) ?? false
  }

  private receivePostResult(event: DiscussionEvent) {
    if (!this.pendingPostId || event.request_id !== this.pendingPostId) return

    if (event.type === "post.saved" && event.message) {
      this.displayCreatedMessage(event.message, event.total_posts)
      this.bodyTarget.value = ""
      this.composerStatusTarget.textContent = "Post published."
    } else if (event.type === "post.rejected") {
      if (event.error === "forbidden") {
        this.composerStatusTarget.textContent = "You do not have permission to post. Your draft is still here."
      } else if (event.error === "rate_limited") {
        this.composerStatusTarget.textContent = "Too many posts. Wait a minute before trying again. Your draft is still here."
      } else {
        const errors = event.errors?.body?.join(", ")
        this.composerStatusTarget.textContent = errors
          ? `Post could not be saved: ${errors}. Your draft is still here.`
          : "Post could not be saved. Your draft is still here."
      }
    } else {
      return
    }
    this.finishPosting()
  }

  private interruptPosting() {
    if (this.posting && this.hasComposerStatusTarget) {
      this.composerStatusTarget.textContent = "Post could not be confirmed. Your draft is still here. Check the discussion before posting again."
    }
    this.finishPosting()
  }

  private finishPosting() {
    clearTimeout(this.postTimeout)
    this.postTimeout = undefined
    this.pendingPostId = undefined
    this.setPosting(false)
  }

  private setPosting(posting: boolean) {
    this.posting = posting
    if (this.hasSubmitTarget) this.submitTarget.disabled = posting || !this.cableConnected
    if (this.hasBodyTarget) this.bodyTarget.readOnly = posting
  }

  endAccess() {
    this.cableConnected = false
    this.finishPosting()
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
    if (this.hasReplyControlsTarget) {
      const controls = this.replyControlsTarget.content.firstElementChild!.cloneNode(true) as HTMLElement
      controls.dataset.clubRepliesPostIdValue = String(message.id)
      controls.dataset.clubRepliesUrlValue = `/book_clubs/${this.bookClubIdValue}/club_messages/${message.id}/replies`
      article.append(controls)
    }
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
