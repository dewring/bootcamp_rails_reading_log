import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { throttle } from "lodash"
import { buildUserAvatar } from "../helpers/user_avatar"

export interface DiscussionMessage {
  id: number
  parent_id: number | null
  body: string
  replies_count?: number
  deleted?: boolean
  author: { id: number; nickname: string; avatar_url?: string | null }
  created_at: string
  updated_at: string
}

export interface DiscussionMember {
  id: number
  nickname: string
  avatar_url?: string | null
}

export interface DiscussionEvent {
  type: string
  message?: DiscussionMessage
  total_posts?: number
  request_id?: string
  errors?: { body?: string[] }
  error?: string
  members?: DiscussionMember[]
  member?: DiscussionMember
  connection_token?: string
  generated_at?: string
}

// Keep fractional seconds when comparing UTC timestamps from Rails.
export function discussionVersion(timestamp: string): string {
  return timestamp.replace(/(?:\.(\d+))?Z$/, (_match, fraction: string = "") => `.${fraction.padEnd(6, "0")}Z`)
}

type DiscussionSubscription = {
  unsubscribe(): void
  perform(action: string, data: { request_id?: string; body?: string; parent_id?: number; message_id?: number }): boolean
}

export default class extends Controller {
  static targets = ["content", "status", "messages", "emptyState", "paginationSummary", "pagination", "body", "submit", "composerStatus", "replyControls", "editor", "deleteButton", "onlineMembers", "presenceStatus", "typingStatus", "typingIndicator"]
  static values = { bookClubId: Number, page: Number, totalPosts: Number, paginationUrl: String, currentUserId: Number, canPost: Boolean, canModerate: Boolean }

  declare readonly contentTarget: HTMLElement
  declare readonly statusTarget: HTMLElement
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

  private paginationVersion = ""
  private paginationRequest?: AbortController
  private messageUpdates = new Map<number, DiscussionMessage>()
  private discussionSubscription?: Promise<DiscussionSubscription | undefined>
  private receivedMessageIds = new Set<number>()
  private posting = false
  private cableConnected = false
  private pendingPostId?: string
  private postTimeout?: ReturnType<typeof setTimeout>
  private heartbeatInterval?: ReturnType<typeof setInterval>
  private snapshotTimeout?: ReturnType<typeof setTimeout>
  private latestPresenceVersion = ""
  private presenceAvailable = false
  private acceptingPresenceEvents = false
  private typingConnections = new Map<string, { member: DiscussionMember; timeout: ReturnType<typeof setTimeout>; version: string }>()
  private throttledTyping = throttle((source: HTMLTextAreaElement, pendingSubscription: Promise<DiscussionSubscription | undefined>, heartbeatInterval: ReturnType<typeof setInterval>) => {
    this.sendTyping(source, pendingSubscription, heartbeatInterval).catch(error => {
      console.error("Failed to send club typing event", error)
    })
  }, 1_000, { leading: true, trailing: false })

  connect() {
    this.acceptingPresenceEvents = true
    this.latestPresenceVersion = ""
    this.showPresenceUnavailable()
    for (const element of this.messagesTarget.children) {
      const article = element as HTMLElement
      this.prepareMessageElement(article, {
        id: Number(article.dataset.messageId),
        author: { id: Number(article.dataset.authorId) },
        updated_at: article.dataset.updatedAt ?? "",
        deleted: article.dataset.deleted === "true"
      })
    }
    this.receivedMessageIds = new Set(
      Array.from(this.messagesTarget.children, message => Number((message as HTMLElement).dataset.messageId))
    )
    const pendingSubscription: Promise<DiscussionSubscription | undefined> = cable.subscribeTo<DiscussionEvent>(
      { channel: "ClubDiscussionChannel", book_club_id: this.bookClubIdValue },
      {
        connected: () => {
          if (this.discussionSubscription !== pendingSubscription) return

          this.cableConnected = true
          this.acceptingPresenceEvents = true
          this.startHeartbeat(pendingSubscription)
          if (this.hasSubmitTarget) this.submitTarget.disabled = this.posting
        },
        received: event => {
          if (this.discussionSubscription !== pendingSubscription) return

          if (event.type === "access.revoked") {
            this.endAccess()
          } else if (event.type === "presence.snapshot") {
            if (this.acceptingPresenceEvents) this.receivePresenceSnapshot(event)
          } else if (event.type === "presence.unavailable") {
            this.showPresenceUnavailable()
          } else if (event.type === "typing.started") {
            if (this.acceptingPresenceEvents) this.receiveTyping(event)
          } else if ((event.type === "message.deleted" || event.type === "reply.deleted") && event.message) {
            this.rememberMessageUpdate(event.message, event.total_posts)
          } else if (event.type === "delete.saved" || event.type === "delete.rejected") {
            if (event.message) this.rememberMessageUpdate(event.message, event.total_posts)
            this.dispatch("delete", { detail: event })
          } else if ((event.type === "message.updated" || event.type === "reply.updated") && event.message) {
            this.rememberMessageUpdate(event.message, event.total_posts)
          } else if (event.type === "edit.saved" || event.type === "edit.rejected") {
            if (event.message) this.rememberMessageUpdate(event.message, event.total_posts)
            this.dispatch("edit", { detail: event })
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
          this.stopHeartbeat()
          this.acceptingPresenceEvents = false
          this.throttledTyping.cancel()
          this.showPresenceUnavailable()
          this.dispatch("connection-ended")
          this.interruptPosting()
          if (!willAttemptReconnect) this.endAccess()
        }
      }
    ).catch(error => {
      console.error("Failed to subscribe to club discussion", error)
      if (this.discussionSubscription === pendingSubscription) {
        this.acceptingPresenceEvents = false
        this.showPresenceUnavailable()
        this.showStatus("Live updates could not connect. Refresh to try again.")
      }
      return undefined
    })

    this.discussionSubscription = pendingSubscription
  }

  disconnect() {
    this.stopHeartbeat()
    this.dispatch("connection-ended")
    this.cableConnected = false
    this.interruptPosting()
    this.unsubscribeFromDiscussion()
    this.messageUpdates.clear()
  }

  beforeCache() {
    this.stopHeartbeat()
    this.cableConnected = false
    this.finishPosting()
    this.contentTarget.replaceChildren()
    this.receivedMessageIds.clear()
    this.messageUpdates.clear()
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
      this.postTimeout = setTimeout(() => this.interruptPosting(), 5_000)
    } catch (error) {
      console.error("Failed to send discussion post", error)
      if (this.pendingPostId === requestId) this.interruptPosting()
    }
  }

  typing(event: Event) {
    const source = event.target
    if (!(source instanceof HTMLTextAreaElement) || source.disabled || source.readOnly || !source.value.trim()) return
    if (!this.canPostValue || !this.cableConnected || !this.discussionSubscription || !this.heartbeatInterval) return

    this.throttledTyping(source, this.discussionSubscription, this.heartbeatInterval)
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
    return this.messageUpdates.get(messageId)
  }

  prepareMessageElement(article: HTMLElement, message: Pick<DiscussionMessage, "id" | "updated_at" | "deleted"> & { author: { id: number } }) {
    const body = article.querySelector<HTMLElement>(".club-discussion-message-body, .club-discussion-reply-body")
    if (!body) return

    article.dataset.deleted = String(message.deleted ?? false)
    article.dataset.controller = "club-message"
    article.dataset.clubMessageMessageIdValue = String(message.id)
    article.dataset.clubMessageUpdatedAtValue = message.updated_at
    article.dataset.clubMessageClubDiscussionOutlet = `#${this.element.id}`
    article.dataset.action = "club-discussion:edit@document->club-message#receiveEdit club-discussion:delete@document->club-message#receiveDelete club-discussion:connection-ended@document->club-message#connectionEnded turbo:before-cache@document->club-message#beforeCache"
    body.dataset.clubMessageTarget = "body"
    if (!message.deleted && this.canPostValue && message.author.id === this.currentUserIdValue && this.hasEditorTarget) {
      if (!article.querySelector("[data-club-message-target='form']")) article.append(this.editorTarget.content.cloneNode(true))
    }
    const canDelete = this.canModerateValue || (this.canPostValue && message.author.id === this.currentUserIdValue)
    if (!message.deleted && canDelete && this.hasDeleteButtonTarget) {
      article.classList.add("club-message-moderatable")
      if (!article.querySelector("[data-club-message-target='deleteButton']")) article.append(this.deleteButtonTarget.content.cloneNode(true))
    }
    if (!article.querySelector("[data-club-message-target='status']")) {
      const status = document.createElement("p")
      status.setAttribute("role", "status")
      status.dataset.clubMessageTarget = "status"
      status.className = "club-message-edit-status"
      const editor = article.querySelector(".club-message-editor")
      if (editor) editor.append(status)
      else article.append(status)
    }
  }

  private async performDiscussionAction(action: string, data: { request_id: string; body?: string; parent_id?: number; message_id?: number }, source: Element): Promise<boolean> {
    if (!this.cableConnected) return false

    const pendingSubscription = this.discussionSubscription
    const subscription = await pendingSubscription
    if (this.discussionSubscription !== pendingSubscription || !this.cableConnected) return false
    if (!source.isConnected || !this.element.contains(source)) return false

    return subscription?.perform(action, data) ?? false
  }

  private rememberMessageUpdate(message: DiscussionMessage, totalPosts?: number) {
    if (!Number.isSafeInteger(message.id) || !Number.isFinite(Date.parse(message.updated_at))) return

    const previous = this.messageUpdates.get(message.id)
    const hidesDeletedPost = message.deleted && message.parent_id === null && message.replies_count === 0
    if (previous?.deleted && (!hidesDeletedPost || previous.replies_count === 0)) return
    if (previous && discussionVersion(message.updated_at) < discussionVersion(previous.updated_at)) return
    if (previous && discussionVersion(message.updated_at) === discussionVersion(previous.updated_at) && !message.deleted) return

    this.messageUpdates.set(message.id, message)
    if (totalPosts !== undefined) this.updatePaginationSummary(totalPosts, message.updated_at, message.deleted === true)
    if (hidesDeletedPost) this.receivedMessageIds.add(message.id)
    if (message.deleted) this.dispatch("delete", { detail: { type: "message.deleted", message } })
    this.dispatch("edit", { detail: { type: "message.updated", message } })
    if (hidesDeletedPost) {
      this.messagesTarget.querySelector(`#club_message_${message.id}`)?.remove()
      this.emptyStateTarget.hidden = this.messagesTarget.childElementCount > 0
    }
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
    this.messageUpdates.clear()
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
    if (totalPosts !== undefined) this.updatePaginationSummary(totalPosts, message.updated_at)

    if (this.pageValue !== 1) {
      this.showStatus("New posts are available on the first page.")
      return
    }

    const latest = this.latestMessageUpdate(message.id)
    const article = this.buildMessageElement(latest ?? message)
    const nextOlderPost = Array.from(this.messagesTarget.children).find(post => {
      return Number((post as HTMLElement).dataset.messageId) < message.id
    })
    if (nextOlderPost) {
      this.messagesTarget.insertBefore(article, nextOlderPost)
    } else {
      this.messagesTarget.append(article)
    }
    this.emptyStateTarget.hidden = true

    while (this.messagesTarget.children.length > 10) {
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
    const timeText = createdAt.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZone: "UTC" })
    time.textContent = `${dateText} · ${timeText}`
    header.append(buildUserAvatar(message.author), author, time)

    const body = document.createElement("p")
    body.className = "club-discussion-message-body"
    body.textContent = message.deleted ? "Deleted post" : message.body
    article.append(header, body)
    this.prepareMessageElement(article, message)
    if (this.hasReplyControlsTarget) {
      const controls = this.replyControlsTarget.content.firstElementChild!.cloneNode(true) as HTMLElement
      controls.dataset.clubRepliesPostIdValue = String(message.id)
      controls.dataset.clubRepliesUrlValue = `/book_clubs/${this.bookClubIdValue}/club_messages/${message.id}/replies`
      controls.dataset.clubRepliesDeletedValue = String(message.deleted ?? false)
      controls.dataset.clubRepliesCountValue = String(message.replies_count ?? 0)
      article.append(controls)
    }
    return article
  }

  private updatePaginationSummary(totalPosts: number, updatedAt: string, allowDecrease = false) {
    if (!Number.isSafeInteger(totalPosts) || totalPosts < 0) return

    const version = discussionVersion(updatedAt)
    if (version < this.paginationVersion) return

    const previousPageCount = Math.max(1, Math.ceil(this.totalPostsValue / 10))
    this.totalPostsValue = version === this.paginationVersion && !allowDecrease
      ? Math.max(this.totalPostsValue, totalPosts)
      : totalPosts
    this.paginationVersion = version
    const pageCount = Math.max(1, Math.ceil(this.totalPostsValue / 10))
    const postLabel = this.totalPostsValue === 1 ? "post" : "posts"
    this.paginationSummaryTarget.textContent = `${this.totalPostsValue} ${postLabel} · Page ${this.pageValue} of ${pageCount}`
    if (pageCount !== previousPageCount) {
      this.refreshPagination(pageCount).catch(error => console.error("Failed to refresh discussion pagination", error))
    }
  }

  private async refreshPagination(pageCount: number) {
    this.paginationRequest?.abort()
    this.paginationRequest = undefined
    if (pageCount === 1) {
      this.paginationTarget.replaceChildren()
      return
    }
    if (!this.paginationUrlValue) return

    const request = new AbortController()
    this.paginationRequest = request
    try {
      const url = new URL(this.paginationUrlValue, window.location.origin)
      url.searchParams.set("page", String(Math.min(this.pageValue, pageCount)))
      const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", signal: request.signal })
      if (this.paginationRequest !== request || !this.element.isConnected) return
      if (response.status === 401 || response.status === 403) {
        this.endAccess()
        return
      }
      if (!response.ok) throw new Error(`Discussion pagination returned ${response.status}`)

      const history: { pagination_html: string } = await response.json()
      if (this.paginationRequest !== request || !this.element.isConnected) return
      // Render the same trusted Rails Pagy partial used on the initial page.
      this.paginationTarget.innerHTML = history.pagination_html
    } catch (error) {
      if (!request.signal.aborted) throw error
    } finally {
      if (this.paginationRequest === request) this.paginationRequest = undefined
    }
  }

  private unsubscribeFromDiscussion() {
    this.paginationRequest?.abort()
    this.paginationRequest = undefined
    this.stopHeartbeat()
    this.acceptingPresenceEvents = false
    this.throttledTyping.cancel()
    this.showPresenceUnavailable()
    const pendingSubscription = this.discussionSubscription
    this.discussionSubscription = undefined

    pendingSubscription?.then(subscription => {
      subscription?.unsubscribe()
    }).catch(error => {
      console.error("Failed to unsubscribe from club discussion", error)
    })
  }

  private receivePresenceSnapshot(event: DiscussionEvent) {
    if (!event.members || !event.generated_at || !Number.isFinite(Date.parse(event.generated_at))) return

    const version = discussionVersion(event.generated_at)
    if (version <= this.latestPresenceVersion) return

    this.latestPresenceVersion = version
    this.presenceAvailable = true
    const members = new Map(event.members.map(member => [member.id, member]))
    if (this.hasOnlineMembersTarget) {
      const orderedMembers = Array.from(members.values()).sort((first, second) => Number(second.id === this.currentUserIdValue) - Number(first.id === this.currentUserIdValue))
      const items = orderedMembers.map(member => this.buildPresenceMember(member))
      this.onlineMembersTarget.replaceChildren(...items)
      this.onlineMembersTarget.hidden = items.length === 0
    }
    if (this.hasPresenceStatusTarget) {
      this.presenceStatusTarget.textContent = `${members.size} ${members.size === 1 ? "member" : "members"} online.`
      this.presenceStatusTarget.classList.add("club-discussion-sr-only")
    }
    for (const [token, connection] of this.typingConnections) {
      const member = members.get(connection.member.id)
      if (member) {
        connection.member = member
      } else {
        clearTimeout(connection.timeout)
        this.typingConnections.delete(token)
      }
    }
    this.renderTyping()
    clearTimeout(this.snapshotTimeout)
    this.snapshotTimeout = setTimeout(() => this.showPresenceUnavailable(), 55_000)
  }

  private buildPresenceMember(member: DiscussionMember): HTMLLIElement {
    const item = document.createElement("li")
    item.className = "club-presence-member"
    item.dataset.memberId = String(member.id)
    const avatar = buildUserAvatar(member)
    const details = document.createElement("span")
    details.className = "club-presence-details"
    const name = document.createElement("strong")
    name.textContent = member.nickname
    const status = document.createElement("span")
    status.className = "club-presence-member-status"
    details.append(name, status)
    item.append(avatar, details)
    return item
  }

  private receiveTyping(event: DiscussionEvent) {
    if (!this.presenceAvailable || !event.member || !event.connection_token || !event.generated_at) return

    const generatedAt = Date.parse(event.generated_at)
    if (!Number.isFinite(generatedAt) || Date.now() - generatedAt >= 3_000) return

    const token = event.connection_token
    const previous = this.typingConnections.get(token)
    const version = discussionVersion(event.generated_at)
    if (previous && version <= previous.version) return

    clearTimeout(previous?.timeout)
    const timeout = setTimeout(() => {
      this.typingConnections.delete(token)
      this.renderTyping()
    }, 3_000)
    this.typingConnections.set(token, { member: event.member, timeout, version })
    this.renderTyping()
  }

  private renderTyping() {
    const members = new Map(Array.from(this.typingConnections.values(), connection => [connection.member.id, connection.member]))
    const names = Array.from(members.values(), member => member.nickname)
    if (this.hasTypingStatusTarget) {
      const announcement = names.length === 0 ? "" : `${names.join(", ")} ${names.length === 1 ? "is" : "are"} typing…`
      if (this.typingStatusTarget.textContent !== announcement) this.typingStatusTarget.textContent = announcement
    }
    if (!this.hasOnlineMembersTarget) return

    for (const item of Array.from(this.onlineMembersTarget.children)) {
      const memberId = Number((item as HTMLElement).dataset.memberId)
      const state = members.has(memberId) ? "Writing a post…" : memberId === this.currentUserIdValue ? "You" : "Online"
      const status = item.querySelector<HTMLElement>(".club-presence-member-status")
      if (!status || status.dataset.state === state) continue

      status.dataset.state = state
      status.replaceChildren()
      if (state === "Writing a post…" && this.hasTypingIndicatorTarget) {
        status.append(this.typingIndicatorTarget.content.cloneNode(true))
      } else {
        status.textContent = state
      }
    }
  }

  private showPresenceUnavailable() {
    this.presenceAvailable = false
    clearTimeout(this.snapshotTimeout)
    this.snapshotTimeout = undefined
    for (const connection of this.typingConnections.values()) {
      clearTimeout(connection.timeout)
    }
    this.typingConnections.clear()
    this.renderTyping()
    if (this.hasOnlineMembersTarget) {
      this.onlineMembersTarget.replaceChildren()
      this.onlineMembersTarget.hidden = true
    }
    if (this.hasPresenceStatusTarget) {
      this.presenceStatusTarget.textContent = "Presence unavailable"
      this.presenceStatusTarget.classList.remove("club-discussion-sr-only")
    }
  }

  private async sendTyping(source: HTMLTextAreaElement, pendingSubscription: Promise<DiscussionSubscription | undefined>, heartbeatInterval: ReturnType<typeof setInterval>) {
    const subscription = await pendingSubscription
    if (this.discussionSubscription !== pendingSubscription || !this.cableConnected || this.heartbeatInterval !== heartbeatInterval) return
    if (!source.isConnected || !this.element.contains(source) || source.readOnly || source.disabled || !source.value.trim()) return

    subscription?.perform("typing", {})
  }

  private startHeartbeat(pendingSubscription: Promise<DiscussionSubscription | undefined>) {
    this.stopHeartbeat()
    const heartbeatInterval = setInterval(() => {
      this.sendHeartbeat(pendingSubscription, heartbeatInterval).catch(error => {
        console.error("Failed to send club presence heartbeat", error)
      })
    }, 10_000)
    this.heartbeatInterval = heartbeatInterval
  }

  private stopHeartbeat() {
    clearInterval(this.heartbeatInterval)
    this.heartbeatInterval = undefined
  }

  private async sendHeartbeat(pendingSubscription: Promise<DiscussionSubscription | undefined>, heartbeatInterval: ReturnType<typeof setInterval>) {
    const subscription = await pendingSubscription
    if (this.discussionSubscription !== pendingSubscription || !this.cableConnected || this.heartbeatInterval !== heartbeatInterval) return

    subscription?.perform("heartbeat", {})
  }
}
