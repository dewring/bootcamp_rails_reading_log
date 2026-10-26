import type { DiscussionEvent, DiscussionMessage, DiscussionSubscription } from "./types"

interface ComposerOptions {
  context(): { connected: boolean; subscription?: Promise<DiscussionSubscription | undefined> }
  targets(): { body?: HTMLTextAreaElement; submit?: HTMLButtonElement; status?: HTMLElement }
  displayCreatedMessage(message: DiscussionMessage, totalPosts?: number): void
}

export default class DiscussionComposer {
  private posting = false
  private pendingPostId?: string
  private postTimeout?: ReturnType<typeof setTimeout>

  constructor(private options: ComposerOptions) {}

  connectionConfirmed() {
    const submit = this.options.targets().submit
    if (submit) submit.disabled = this.posting
  }

  disconnect() {
    this.interruptPosting()
  }

  reset() {
    this.finishPosting()
  }

  private get cableConnected() {
    return this.options.context().connected
  }
  private get discussionSubscription() {
    return this.options.context().subscription
  }
  private get hasBodyTarget() {
    return this.options.targets().body !== undefined
  }
  private get hasSubmitTarget() {
    return this.options.targets().submit !== undefined
  }
  private get hasComposerStatusTarget() {
    return this.options.targets().status !== undefined
  }
  private get bodyTarget() {
    return this.options.targets().body!
  }
  private get submitTarget() {
    return this.options.targets().submit!
  }
  private get composerStatusTarget() {
    return this.options.targets().status!
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

  receivePostResult(event: DiscussionEvent) {
    if (!this.pendingPostId || event.request_id !== this.pendingPostId) {
      // A late success still belongs in the feed, but must not clear a newer draft.
      if (event.type === "post.saved" && event.message) this.options.displayCreatedMessage(event.message, event.total_posts)
      return
    }

    if (event.type === "post.saved" && event.message) {
      this.options.displayCreatedMessage(event.message, event.total_posts)
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
}
