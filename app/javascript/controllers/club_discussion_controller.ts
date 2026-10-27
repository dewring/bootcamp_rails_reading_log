import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import ClubPresence from "../club_discussion/presence"
import DiscussionRecovery from "../club_discussion/recovery"
import DiscussionFeed from "../club_discussion/feed"
import DiscussionComposer from "../club_discussion/composer"
import type { DiscussionEvent, DiscussionMessage, DiscussionSubscription } from "../club_discussion/types"

export default class extends Controller {
  static targets = ["content", "status", "connectionStatus", "retry", "messages", "emptyState", "paginationSummary", "pagination", "body", "submit", "composerStatus", "replyControls", "editor", "deleteButton", "onlineMembers", "presenceStatus", "typingStatus", "typingIndicator"]
  static values = { bookClubId: Number, page: Number, totalPosts: Number, paginationUrl: String, currentUserId: Number, canPost: Boolean, canModerate: Boolean }

  declare readonly contentTarget: HTMLElement
  declare readonly statusTarget: HTMLElement
  declare readonly hasConnectionStatusTarget: boolean
  declare readonly connectionStatusTarget: HTMLElement
  declare readonly hasRetryTarget: boolean
  declare readonly retryTarget: HTMLButtonElement
  declare readonly bookClubIdValue: number
  declare readonly pageValue: number
  declare totalPostsValue: number
  declare readonly messagesTarget: HTMLElement
  declare readonly emptyStateTarget: HTMLElement
  declare readonly paginationSummaryTarget: HTMLElement
  declare readonly paginationTarget: HTMLElement
  declare readonly paginationUrlValue: string
  declare readonly hasBodyTarget: boolean
  declare readonly hasSubmitTarget: boolean
  declare readonly hasComposerStatusTarget: boolean
  declare readonly bodyTarget: HTMLTextAreaElement
  declare readonly submitTarget: HTMLButtonElement
  declare readonly composerStatusTarget: HTMLElement

  declare readonly replyControlsTarget: HTMLTemplateElement
  declare readonly hasReplyControlsTarget: boolean

  declare readonly editorTarget: HTMLTemplateElement
  declare readonly hasEditorTarget: boolean
  declare readonly deleteButtonTarget: HTMLTemplateElement
  declare readonly hasDeleteButtonTarget: boolean
  declare readonly canModerateValue: boolean
  declare readonly currentUserIdValue: number
  declare readonly canPostValue: boolean
  declare readonly hasOnlineMembersTarget: boolean
  declare readonly onlineMembersTarget: HTMLUListElement
  declare readonly hasPresenceStatusTarget: boolean
  declare readonly presenceStatusTarget: HTMLElement
  declare readonly hasTypingStatusTarget: boolean
  declare readonly typingStatusTarget: HTMLElement
  declare readonly hasTypingIndicatorTarget: boolean
  declare readonly typingIndicatorTarget: HTMLTemplateElement

  private feed!: DiscussionFeed
  private composer!: DiscussionComposer
  private recovery?: DiscussionRecovery
  private discussionSubscription?: Promise<DiscussionSubscription | undefined>
  private cableConnected = false
  private presence?: ClubPresence

  connect() {
    this.feed = new DiscussionFeed({
      root: this.element as HTMLElement,
      context: () => ({
        page: this.pageValue,
        url: this.paginationUrlValue,
        totalPosts: this.totalPostsValue,
        bookClubId: this.bookClubIdValue,
        currentUserId: this.currentUserIdValue,
        canPost: this.canPostValue,
        canModerate: this.canModerateValue
      }),
      targets: () => ({
        messages: this.messagesTarget,
        emptyState: this.emptyStateTarget,
        summary: this.paginationSummaryTarget,
        pagination: this.paginationTarget,
        editor: this.hasEditorTarget ? this.editorTarget : undefined,
        deleteButton: this.hasDeleteButtonTarget ? this.deleteButtonTarget : undefined,
        replyControls: this.hasReplyControlsTarget ? this.replyControlsTarget : undefined
      }),
      setTotalPosts: total => {
        this.totalPostsValue = total
      },
      bufferEvent: event => this.recovery?.bufferEvent(event) ?? false,
      isRecovering: () => this.recovery?.isRecovering ?? false,
      dispatch: (name, options) => {
        this.dispatch(name, options)
      },
      showStatus: message => this.showStatus(message),
      endAccess: () => this.endAccess()
    })
    this.composer = new DiscussionComposer({
      context: () => ({ connected: this.cableConnected, subscription: this.discussionSubscription }),
      targets: () => ({
        body: this.hasBodyTarget ? this.bodyTarget : undefined,
        submit: this.hasSubmitTarget ? this.submitTarget : undefined,
        status: this.hasComposerStatusTarget ? this.composerStatusTarget : undefined
      }),
      displayCreatedMessage: (message, total) => this.feed.displayCreatedMessage(message, total)
    })
    this.recovery = new DiscussionRecovery({
      root: this.element as HTMLElement,
      context: () => ({
        connected: this.cableConnected,
        subscription: this.discussionSubscription,
        url: this.paginationUrlValue,
        page: this.pageValue
      }),
      targets: () => ({
        status: this.hasConnectionStatusTarget ? this.connectionStatusTarget : undefined,
        retry: this.hasRetryTarget ? this.retryTarget : undefined
      }),
      beforeRead: () => this.feed.pagination.cancelRead(),
      applyHistory: (history, events) => this.feed.applyRecoveredHistory(history, events),
      replayEvents: events => this.feed.replayRecoveryEvents(events),
      endAccess: () => this.endAccess()
    })
    this.presence = new ClubPresence({
      root: this.element as HTMLElement,
      currentUserId: () => this.currentUserIdValue,
      canPost: () => this.canPostValue,
      targets: () => ({
        onlineMembers: this.hasOnlineMembersTarget ? this.onlineMembersTarget : undefined,
        presenceStatus: this.hasPresenceStatusTarget ? this.presenceStatusTarget : undefined,
        typingStatus: this.hasTypingStatusTarget ? this.typingStatusTarget : undefined,
        typingIndicator: this.hasTypingIndicatorTarget ? this.typingIndicatorTarget : undefined
      })
    })
    const pendingSubscription: Promise<DiscussionSubscription | undefined> = cable.subscribeTo<DiscussionEvent>(
      { channel: "ClubDiscussionChannel", book_club_id: this.bookClubIdValue },
      {
        connected: () => {
          if (this.discussionSubscription !== pendingSubscription) return

          this.cableConnected = true
          this.presence?.subscriptionConfirmed(pendingSubscription)
          this.composer.connectionConfirmed()
          this.recoverDiscussion().catch(error => console.error("Failed to start discussion recovery", error))
        },
        received: event => {
          if (this.discussionSubscription !== pendingSubscription) return

          if (event.type === "access.revoked") {
            this.endAccess()
          } else if (event.type === "presence.snapshot" || event.type === "presence.unavailable" || event.type === "typing.started") {
            this.presence?.receiveEvent(event)
          } else if ((event.type === "message.deleted" || event.type === "reply.deleted") && event.message) {
            this.feed.rememberMessageUpdate(event.message, event.total_posts)
          } else if (event.type === "delete.saved" || event.type === "delete.rejected") {
            if (event.message) this.feed.rememberMessageUpdate(event.message, event.total_posts)
            this.dispatch("delete", { detail: event })
          } else if ((event.type === "message.updated" || event.type === "reply.updated") && event.message) {
            this.feed.rememberMessageUpdate(event.message, event.total_posts)
          } else if (event.type === "edit.saved" || event.type === "edit.rejected") {
            if (event.message) this.feed.rememberMessageUpdate(event.message, event.total_posts)
            this.dispatch("edit", { detail: event })
          } else if (event.type === "message.created" && event.message) {
            this.feed.displayCreatedMessage(event.message, event.total_posts)
          } else if (event.type === "reply.created" || event.type === "reply.saved" || event.type === "reply.rejected") {
            this.dispatch("reply", { detail: event })
          } else if (event.type === "post.saved" || event.type === "post.rejected") {
            this.composer.receivePostResult(event)
          }
        },
        rejected: () => {
          if (this.discussionSubscription === pendingSubscription) this.endAccess()
        },
        disconnected: ({ willAttemptReconnect }) => {
          if (this.discussionSubscription !== pendingSubscription) return

          this.cableConnected = false
          this.recovery?.connectionLost()
          this.presence?.disconnect()
          this.dispatch("connection-ended")
          this.composer.disconnect()
          if (!willAttemptReconnect) this.endAccess()
        }
      }
    ).catch(error => {
      console.error("Failed to subscribe to club discussion", error)
      if (this.discussionSubscription === pendingSubscription) {
        this.presence?.disconnect()
        this.showStatus("Live updates could not connect. Refresh to try again.")
        this.recovery?.connectionLost()
      }
      return undefined
    })

    this.discussionSubscription = pendingSubscription
  }

  disconnect() {
    this.dispatch("connection-ended")
    this.cableConnected = false
    this.composer.disconnect()
    this.unsubscribeFromDiscussion()
    this.feed.disconnect()
  }

  beforeCache() {
    this.cableConnected = false
    this.composer.reset()
    this.contentTarget.replaceChildren()
    this.feed.reset()
    this.unsubscribeFromDiscussion()
  }

  async recoverDiscussion() {
    const recovery = this.recovery
    const history = await recovery?.recoverPage()
    if (!history || this.recovery !== recovery || !this.cableConnected || !this.element.isConnected) return

    this.feed.pagination.refreshAfterRecovery(history.total_posts)
  }

  async postMessage(event: SubmitEvent) {
    await this.composer.postMessage(event)
  }

  prepareMessageElement(article: HTMLElement, message: Pick<DiscussionMessage, "id" | "updated_at" | "deleted"> & { author: { id: number } }) {
    this.feed.prepareMessageElement(article, message)
  }

  typing(event: Event) {
    this.presence?.typing(event)
  }

  sendReply(requestId: string, parentId: number, body: string, composer: Element): Promise<boolean> {
    return this.performDiscussionAction("post_reply", { request_id: requestId, parent_id: parentId, body }, composer)
  }

  sendEdit(requestId: string, messageId: number, body: string, editor: Element): Promise<boolean> {
    return this.performDiscussionAction("update_message", { request_id: requestId, message_id: messageId, body }, editor)
  }

  sendDelete(requestId: string, messageId: number, source: Element): Promise<boolean> {
    return this.performDiscussionAction("delete_message", { request_id: requestId, message_id: messageId }, source)
  }

  latestMessageUpdate(messageId: number) {
    return this.feed.latestMessageUpdate(messageId)
  }

  private async performDiscussionAction(action: string, data: { request_id: string; body?: string; parent_id?: number; message_id?: number }, source: Element): Promise<boolean> {
    if (!this.cableConnected) return false

    const pendingSubscription = this.discussionSubscription
    const subscription = await pendingSubscription
    if (this.discussionSubscription !== pendingSubscription || !this.cableConnected) return false
    if (!source.isConnected || !this.element.contains(source)) return false

    return subscription?.perform(action, data) ?? false
  }

  endAccess() {
    this.cableConnected = false
    this.composer.reset()
    this.contentTarget.replaceChildren()
    this.feed.reset()
    this.showStatus("Discussion access has ended. Sign in or reopen the club to continue.")
    this.unsubscribeFromDiscussion()
  }

  private showStatus(message: string) {
    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
  }

  private unsubscribeFromDiscussion() {
    this.recovery?.disconnect()
    this.presence?.disconnect()
    const pendingSubscription = this.discussionSubscription
    this.discussionSubscription = undefined

    pendingSubscription?.then(subscription => {
      subscription?.unsubscribe()
    }).catch(error => {
      console.error("Failed to unsubscribe from club discussion", error)
    })
  }
}
