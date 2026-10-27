import { discussionVersion } from "./message_version"
import { buildMessageElement, prepareMessageElement, type MessageElementOptions } from "./message_elements"
import DiscussionPagination from "./pagination"
import type { DiscussionEvent, DiscussionHistory, DiscussionMessage } from "./types"

interface FeedTargets {
  messages: HTMLElement
  emptyState: HTMLElement
  summary: HTMLElement
  pagination: HTMLElement
  editor?: HTMLTemplateElement
  deleteButton?: HTMLTemplateElement
  replyControls?: HTMLTemplateElement
}

interface FeedOptions {
  root: HTMLElement
  context(): { page: number; url: string; totalPosts: number; bookClubId: number; currentUserId: number; canPost: boolean; canModerate: boolean }
  targets(): FeedTargets
  setTotalPosts(total: number): void
  bufferEvent(event: DiscussionEvent): boolean
  isRecovering(): boolean
  dispatch(name: string, options: { detail: DiscussionEvent }): void
  showStatus(message: string): void
  endAccess(): void
}

export default class DiscussionFeed {
  readonly pagination: DiscussionPagination
  private messageUpdates = new Map<number, DiscussionMessage>()
  private receivedMessageIds = new Set<number>()

  constructor(private options: FeedOptions) {
    this.pagination = new DiscussionPagination({
      root: options.root,
      context: options.context,
      targets: () => ({ summary: options.targets().summary, links: options.targets().pagination }),
      setTotalPosts: options.setTotalPosts,
      isRecovering: options.isRecovering,
      endAccess: options.endAccess
    })
    for (const element of this.messagesTarget.children) {
      const article = element as HTMLElement
      this.prepareMessageElement(article, {
        id: Number(article.dataset.messageId),
        author: { id: Number(article.dataset.authorId) },
        updated_at: article.dataset.updatedAt ?? "",
        deleted: article.dataset.deleted === "true"
      })
    }
    this.receivedMessageIds = new Set(Array.from(this.messagesTarget.children, message => Number((message as HTMLElement).dataset.messageId)))
  }

  disconnect() {
    this.pagination.cancelRead()
    this.messageUpdates.clear()
  }

  reset() {
    this.disconnect()
    this.receivedMessageIds.clear()
  }

  latestMessageUpdate(messageId: number) {
    return this.messageUpdates.get(messageId)
  }

  prepareMessageElement(article: HTMLElement, message: Pick<DiscussionMessage, "id" | "updated_at" | "deleted"> & { author: { id: number } }) {
    prepareMessageElement(article, message, this.messageOptions())
  }

  private buildMessageElement(message: DiscussionMessage) {
    return buildMessageElement(message, this.messageOptions())
  }

  private messageOptions(): MessageElementOptions {
    return { rootId: this.options.root.id, ...this.options.context(), ...this.options.targets() }
  }

  private get pageValue() {
    return this.options.context().page
  }
  private get totalPostsValue() {
    return this.options.context().totalPosts
  }
  private get messagesTarget() {
    return this.options.targets().messages
  }
  private get emptyStateTarget() {
    return this.options.targets().emptyState
  }

  applyRecoveredHistory(history: DiscussionHistory, events: DiscussionEvent[]) {
    const recovered = new Map<number, DiscussionMessage>()
    for (const message of history.messages) {
      const known = this.messageUpdates.get(message.id)
      recovered.set(message.id, known && discussionVersion(known.updated_at) >= discussionVersion(message.updated_at) ? known : message)
    }
    for (const event of events) {
      const message = event.message
      if (!message || message.parent_id !== null) continue
      if (this.pageValue !== 1 && !recovered.has(message.id)) continue

      const previous = recovered.get(message.id)
      if (previous?.deleted && !message.deleted) continue
      if (previous && discussionVersion(previous.updated_at) > discussionVersion(message.updated_at)) continue
      recovered.set(message.id, message)
    }
    const posts = Array.from(recovered.values())
      .filter(message => !message.deleted || (message.replies_count ?? 0) > 0)
      .sort((first, second) => second.id - first.id)
      .slice(0, 10)
    const ids = new Set(posts.map(message => message.id))
    for (const element of Array.from(this.messagesTarget.children)) {
      if (!ids.has(Number((element as HTMLElement).dataset.messageId))) element.remove()
    }
    for (const [index, message] of posts.entries()) {
      const existing = this.messagesTarget.querySelector<HTMLElement>(`#club_message_${message.id}`)
      const article = existing ?? this.buildMessageElement(message)
      if (existing) this.rememberMessageUpdate(message)
      const controls = article.querySelector<HTMLElement>("[data-controller~='club-replies']")
      if (controls) controls.dataset.clubRepliesCountValue = String(message.replies_count ?? 0)
      const position = this.messagesTarget.children[index] ?? null
      if (position !== article) this.messagesTarget.insertBefore(article, position)
    }
    this.receivedMessageIds = ids
    this.emptyStateTarget.hidden = posts.length > 0
    this.pagination.showHistory(history)
    this.replayRecoveryEvents(events)
  }

  replayRecoveryEvents(events: DiscussionEvent[]) {
    for (const event of events) {
      if (!event.message) continue
      const totalPosts = event.total_posts === undefined ? undefined : event.message.deleted
        ? Math.min(this.totalPostsValue, event.total_posts)
        : Math.max(this.totalPostsValue, event.total_posts)
      if (event.type === "message.created") this.displayCreatedMessage(event.message, totalPosts)
      else this.rememberMessageUpdate(event.message, totalPosts)
    }
  }

  rememberMessageUpdate(message: DiscussionMessage, totalPosts?: number) {
    if (this.options.bufferEvent({ type: "message.updated", message, total_posts: totalPosts })) return

    if (!Number.isSafeInteger(message.id) || !Number.isFinite(Date.parse(message.updated_at))) return

    const previous = this.messageUpdates.get(message.id)
    const hidesDeletedPost = message.deleted && message.parent_id === null && message.replies_count === 0
    if (previous?.deleted && (!hidesDeletedPost || previous.replies_count === 0)) return
    if (previous && discussionVersion(message.updated_at) < discussionVersion(previous.updated_at)) return
    if (previous && discussionVersion(message.updated_at) === discussionVersion(previous.updated_at) && !message.deleted) return

    this.messageUpdates.set(message.id, message)
    if (totalPosts !== undefined) this.pagination.updateSummary(totalPosts, message.updated_at, message.deleted === true)
    if (hidesDeletedPost) this.receivedMessageIds.add(message.id)
    if (message.deleted) this.options.dispatch("delete", { detail: { type: "message.deleted", message } })
    this.options.dispatch("edit", { detail: { type: "message.updated", message } })
    if (hidesDeletedPost) {
      this.messagesTarget.querySelector(`#club_message_${message.id}`)?.remove()
      this.emptyStateTarget.hidden = this.messagesTarget.childElementCount > 0
    }
  }

  displayCreatedMessage(message: DiscussionMessage, totalPosts?: number) {
    if (this.options.bufferEvent({ type: "message.created", message, total_posts: totalPosts })) return

    if (!Number.isSafeInteger(message.id) || message.id <= 0) return
    if (this.receivedMessageIds.has(message.id)) return

    this.receivedMessageIds.add(message.id)
    if (totalPosts !== undefined) this.pagination.updateSummary(totalPosts, message.updated_at)

    if (this.pageValue !== 1) {
      this.options.showStatus("New posts are available on the first page.")
      return
    }

    const latest = this.latestMessageUpdate(message.id)
    if (latest?.deleted && latest.replies_count === 0) return
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
}
