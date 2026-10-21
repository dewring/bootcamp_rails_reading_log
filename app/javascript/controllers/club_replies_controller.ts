import { buildUserAvatar } from "../helpers/user_avatar"
import { Controller } from "@hotwired/stimulus"
import type ClubDiscussionController from "./club_discussion_controller"
import type { DiscussionEvent, DiscussionMessage } from "./club_discussion_controller"

interface ReplyHistory {
  replies: DiscussionMessage[]
  pagination: { next_page: number | null }
}

export default class extends Controller {
  static targets = ["toggle", "panel", "list", "status", "more", "body", "label", "submit", "cancel", "composerStatus", "form"]
  static outlets = ["club-discussion"]
  static values = { url: String, postId: Number, deleted: Boolean }

  declare deletedValue: boolean
  declare readonly hasFormTarget: boolean
  declare readonly formTarget: HTMLFormElement
  declare readonly urlValue: string
  declare readonly postIdValue: number
  declare readonly toggleTarget: HTMLButtonElement
  declare readonly panelTarget: HTMLElement
  declare readonly listTarget: HTMLElement
  declare readonly statusTarget: HTMLElement
  declare readonly moreTarget: HTMLButtonElement

  declare readonly hasBodyTarget: boolean
  declare readonly bodyTarget: HTMLTextAreaElement
  declare readonly labelTarget: HTMLLabelElement
  declare readonly submitTarget: HTMLButtonElement
  declare readonly cancelTarget: HTMLButtonElement
  declare readonly composerStatusTarget: HTMLElement
  declare readonly hasClubDiscussionOutlet: boolean
  declare readonly clubDiscussionOutlet: ClubDiscussionController

  private pendingReplyId?: string
  private replyTimeout?: ReturnType<typeof setTimeout>
  private request?: AbortController
  private loaded = false
  private nextPage: number | null = 1
  private displayedIds = new Set<number>()

  connect() {
    this.panelTarget.id = `club_replies_${this.postIdValue}`
    this.toggleTarget.setAttribute("aria-controls", this.panelTarget.id)
    if (this.hasBodyTarget) {
      this.bodyTarget.id = `club_reply_body_${this.postIdValue}`
      this.labelTarget.htmlFor = this.bodyTarget.id
    }
    const latest = this.hasClubDiscussionOutlet ? this.clubDiscussionOutlet.latestMessageUpdate(this.postIdValue) : undefined
    if (this.deletedValue || latest?.deleted) this.disableReplies()
  }

  disconnect() {
    this.interruptPosting()
    this.request?.abort()
    this.request = undefined
  }

  beforeCache() {
    this.disconnect()
    if (this.hasBodyTarget) {
      this.bodyTarget.value = ""
      this.composerStatusTarget.textContent = ""
    }
    this.listTarget.replaceChildren()
    this.displayedIds.clear()
    this.loaded = false
    this.nextPage = 1
    this.panelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.statusTarget.textContent = ""
  }

  async toggle() {
    const expanded = this.panelTarget.hidden
    this.panelTarget.hidden = !expanded
    this.toggleTarget.setAttribute("aria-expanded", String(expanded))
    if (expanded && !this.loaded) await this.loadMore()
  }

  async loadMore() {
    if (this.request || this.nextPage === null) return

    const request = new AbortController()
    this.request = request
    this.moreTarget.disabled = true
    this.statusTarget.textContent = "Loading replies…"

    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("page", String(this.nextPage))
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        signal: request.signal
      })
      if (this.request !== request || !this.element.isConnected) return
      if (response.status === 401 || response.status === 403) {
        this.dispatch("access-revoked")
        return
      }
      if (!response.ok) throw new Error(`Reply history returned ${response.status}`)

      const history: ReplyHistory = await response.json()
      if (this.request !== request || !this.element.isConnected) return
      for (const reply of history.replies) this.displayReply(reply)
      this.loaded = true
      this.nextPage = history.pagination.next_page
      this.moreTarget.hidden = this.nextPage === null
      this.statusTarget.textContent = this.displayedIds.size === 0 ? "No replies yet." : ""
    } catch (error) {
      if (this.request !== request || request.signal.aborted) return

      console.error("Failed to load discussion replies", error)
      this.statusTarget.textContent = "Replies could not load. Try again."
      this.moreTarget.hidden = false
    } finally {
      if (this.request === request) {
        this.request = undefined
        this.moreTarget.disabled = false
      }
    }
  }

  async postReply(event: SubmitEvent) {
    event.preventDefault()
    if (this.pendingReplyId || this.deletedValue) return
    if (!this.hasClubDiscussionOutlet) {
      this.composerStatusTarget.textContent = "Live connection is not ready. Your draft is still here."
      return
    }

    const requestId = crypto.randomUUID()
    this.pendingReplyId = requestId
    this.setPosting(true)
    this.composerStatusTarget.textContent = "Posting reply…"
    try {
      const sent = await this.clubDiscussionOutlet.sendReply(requestId, this.postIdValue, this.bodyTarget.value, this.element)
      if (this.pendingReplyId !== requestId || !this.element.isConnected) return
      if (!sent) {
        this.interruptPosting()
        return
      }

      // A missing acknowledgement does not prove that saving failed; never retry automatically.
      this.replyTimeout = setTimeout(() => this.interruptPosting(), 5_000)
    } catch (error) {
      console.error("Failed to send discussion reply", error)
      if (this.pendingReplyId === requestId) this.interruptPosting()
    }
  }

  receiveReply(event: CustomEvent<DiscussionEvent>) {
    if (!this.belongsToDiscussion(event)) return

    const result = event.detail
    if (result.type === "reply.created" && result.message) {
      if (this.loaded || !this.panelTarget.hidden) this.displayReply(result.message)
      return
    }
    if (!this.pendingReplyId || result.request_id !== this.pendingReplyId) return

    if (result.type === "reply.saved" && result.message?.parent_id === this.postIdValue) {
      this.displayReply(result.message)
      this.bodyTarget.value = ""
      this.composerStatusTarget.textContent = "Reply published."
    } else if (result.type === "reply.rejected") {
      if (result.error === "rate_limited") {
        this.composerStatusTarget.textContent = "Too many posts or replies. Wait a minute before trying again. Your draft is still here."
      } else if (result.error === "forbidden") {
        this.composerStatusTarget.textContent = "You do not have permission to reply. Your draft is still here."
      } else if (result.error === "not_found") {
        this.composerStatusTarget.textContent = "This post is no longer available for replies. Your draft is still here."
      } else {
        const errors = result.errors?.body?.join(", ")
        this.composerStatusTarget.textContent = errors
          ? `Reply could not be saved: ${errors}. Your draft is still here.`
          : "Reply could not be saved. Your draft is still here."
      }
    } else {
      return
    }
    this.finishPosting()
  }

  receiveDelete(event: CustomEvent<DiscussionEvent>) {
    if (!this.belongsToDiscussion(event)) return
    const message = event.detail.message
    if (!message?.deleted) return

    if (message.id === this.postIdValue) this.disableReplies()
    if (message.parent_id === this.postIdValue) {
      this.listTarget.querySelector(`#club_message_${message.id}`)?.remove()
      this.displayedIds.delete(message.id)
    }
  }

  private disableReplies() {
    this.deletedValue = true
    this.finishPosting()
    if (this.hasBodyTarget) this.bodyTarget.value = ""
    if (this.hasFormTarget) this.formTarget.remove()
  }

  connectionEnded(event: Event) {
    if (this.belongsToDiscussion(event)) this.interruptPosting()
  }

  cancelReply() {
    if (this.pendingReplyId || this.deletedValue) return

    this.bodyTarget.value = ""
    this.composerStatusTarget.textContent = ""
    this.panelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
  }

  private belongsToDiscussion(event: Event) {
    return event.target === this.element.closest("[data-controller~='club-discussion']")
  }

  private interruptPosting() {
    if (this.pendingReplyId && this.hasBodyTarget) {
      this.composerStatusTarget.textContent = "Reply could not be confirmed. Your draft is still here. Check the replies before posting again."
    }
    this.finishPosting()
  }

  private finishPosting() {
    clearTimeout(this.replyTimeout)
    this.replyTimeout = undefined
    this.pendingReplyId = undefined
    this.setPosting(false)
  }

  private setPosting(posting: boolean) {
    if (!this.hasBodyTarget) return

    this.bodyTarget.readOnly = posting
    this.submitTarget.disabled = posting
    this.cancelTarget.disabled = posting
  }

  private displayReply(reply: DiscussionMessage) {
    if (reply.parent_id !== this.postIdValue || !Number.isSafeInteger(reply.id) || reply.id <= 0) return
    if (this.displayedIds.has(reply.id)) return

    const latest = this.hasClubDiscussionOutlet ? this.clubDiscussionOutlet.latestMessageUpdate(reply.id) : undefined
    if (reply.deleted || latest?.deleted) return
    if (latest) reply = latest

    this.displayedIds.add(reply.id)
    const article = document.createElement("article")
    article.id = `club_message_${reply.id}`
    article.className = "club-discussion-reply"
    const header = document.createElement("header")
    header.className = "club-discussion-reply-header"
    const avatar = buildUserAvatar(reply.author)
    const identity = document.createElement("div")
    identity.className = "club-discussion-reply-author"
    const author = document.createElement("strong")
    author.textContent = reply.author.nickname
    const time = document.createElement("time")
    time.dateTime = reply.created_at
    time.textContent = new Date(reply.created_at).toLocaleString("en-US", { timeZone: "UTC", year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    identity.append(author, time)
    header.append(avatar, identity)
    const body = document.createElement("p")
    body.textContent = reply.body
    body.className = "club-discussion-reply-body"
    article.append(header, body)
    if (this.hasClubDiscussionOutlet) this.clubDiscussionOutlet.prepareMessageElement(article, reply)
    article.dataset.replyId = String(reply.id)
    const newerReply = Array.from(this.listTarget.children).find(element => Number((element as HTMLElement).dataset.replyId) > reply.id)
    if (newerReply) {
      this.listTarget.insertBefore(article, newerReply)
    } else {
      this.listTarget.append(article)
    }
    this.statusTarget.textContent = ""
  }
}
