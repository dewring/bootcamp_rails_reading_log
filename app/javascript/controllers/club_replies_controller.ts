import { Controller } from "@hotwired/stimulus"
import type { DiscussionMessage } from "./club_discussion_controller"

interface ReplyHistory {
  replies: DiscussionMessage[]
  pagination: { next_page: number | null }
}

export default class extends Controller {
  static targets = ["toggle", "panel", "list", "status", "more"]
  static values = { url: String, postId: Number }

  declare readonly urlValue: string
  declare readonly postIdValue: number
  declare readonly toggleTarget: HTMLButtonElement
  declare readonly panelTarget: HTMLElement
  declare readonly listTarget: HTMLElement
  declare readonly statusTarget: HTMLElement
  declare readonly moreTarget: HTMLButtonElement

  private request?: AbortController
  private loaded = false
  private nextPage: number | null = 1
  private displayedIds = new Set<number>()

  connect() {
    this.panelTarget.id = `club_replies_${this.postIdValue}`
    this.toggleTarget.setAttribute("aria-controls", this.panelTarget.id)
  }

  disconnect() {
    this.request?.abort()
    this.request = undefined
  }

  beforeCache() {
    this.disconnect()
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

  private displayReply(reply: DiscussionMessage) {
    if (reply.parent_id !== this.postIdValue || !Number.isSafeInteger(reply.id) || reply.id <= 0) return
    if (this.displayedIds.has(reply.id)) return

    this.displayedIds.add(reply.id)
    const article = document.createElement("article")
    article.id = `club_message_${reply.id}`
    article.className = "club-discussion-reply"
    const header = document.createElement("header")
    header.className = "club-discussion-reply-header"
    const avatar = document.createElement("span")
    avatar.className = "club-discussion-reply-avatar"
    avatar.setAttribute("aria-hidden", "true")
    avatar.textContent = reply.author.nickname.slice(0, 2).toUpperCase()
    const identity = document.createElement("div")
    identity.className = "club-discussion-reply-author"
    const author = document.createElement("strong")
    author.textContent = reply.author.nickname
    const time = document.createElement("time")
    time.dateTime = reply.created_at
    time.textContent = new Date(reply.created_at).toLocaleString("en-GB", { timeZone: "UTC", year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })
    identity.append(author, time)
    header.append(avatar, identity)
    const body = document.createElement("p")
    body.textContent = reply.body
    article.append(header, body)
    this.listTarget.append(article)
  }
}
