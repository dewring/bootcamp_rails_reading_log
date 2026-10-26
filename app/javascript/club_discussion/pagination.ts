import { discussionVersion } from "./message_version"
import { discussionAccessDenied } from "./recovery"
import type { DiscussionHistory } from "./types"

interface PaginationOptions {
  root: HTMLElement
  context(): { page: number; url: string; totalPosts: number }
  targets(): { summary: HTMLElement; links: HTMLElement }
  setTotalPosts(total: number): void
  isRecovering(): boolean
  endAccess(): void
}

export default class DiscussionPagination {
  private paginationVersion = ""
  private paginationRequest?: AbortController

  constructor(private options: PaginationOptions) {}

  cancelRead() {
    this.paginationRequest?.abort()
    this.paginationRequest = undefined
  }

  showHistory(history: DiscussionHistory) {
    this.totalPostsValue = history.total_posts
    this.paginationVersion = ""
    this.paginationTarget.innerHTML = history.pagination_html
    const label = history.total_posts === 1 ? "post" : "posts"
    this.paginationSummaryTarget.textContent = `${history.total_posts} ${label} · Page ${this.pageValue} of ${Math.max(1, Math.ceil(history.total_posts / 10))}`
  }

  refreshAfterRecovery(snapshotTotal: number) {
    if (snapshotTotal === this.totalPostsValue) return

    this.refresh(Math.max(1, Math.ceil(this.totalPostsValue / 10)))
      .catch(error => console.error("Failed to refresh discussion pagination", error))
  }

  private get element() {
    return this.options.root
  }
  private get pageValue() {
    return this.options.context().page
  }
  private get paginationUrlValue() {
    return this.options.context().url
  }
  private get totalPostsValue() {
    return this.options.context().totalPosts
  }
  private set totalPostsValue(total: number) {
    this.options.setTotalPosts(total)
  }
  private get paginationSummaryTarget() {
    return this.options.targets().summary
  }
  private get paginationTarget() {
    return this.options.targets().links
  }

  updateSummary(totalPosts: number, updatedAt: string, allowDecrease = false) {
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
    if (pageCount !== previousPageCount && !this.options.isRecovering()) {
      this.refresh(pageCount).catch(error => console.error("Failed to refresh discussion pagination", error))
    }
  }

  async refresh(pageCount: number) {
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
      if (discussionAccessDenied(response)) {
        this.options.endAccess()
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
}
