import { Controller } from "@hotwired/stimulus"
import type ClubDiscussionController from "./club_discussion_controller"
import { discussionVersion, type DiscussionEvent, type DiscussionMessage } from "./club_discussion_controller"

export default class extends Controller {
  static targets = ["body", "form", "editButton", "input", "label", "save", "cancel", "status"]
  static values = { messageId: Number, updatedAt: String }
  static outlets = ["club-discussion"]

  declare readonly messageIdValue: number
  declare updatedAtValue: string
  declare readonly bodyTarget: HTMLElement
  declare readonly hasFormTarget: boolean
  declare readonly formTarget: HTMLFormElement
  declare readonly editButtonTarget: HTMLButtonElement
  declare readonly inputTarget: HTMLTextAreaElement
  declare readonly labelTarget: HTMLLabelElement
  declare readonly saveTarget: HTMLButtonElement
  declare readonly cancelTarget: HTMLButtonElement
  declare readonly statusTarget: HTMLElement
  declare readonly hasClubDiscussionOutlet: boolean
  declare readonly clubDiscussionOutlet: ClubDiscussionController

  private pendingEditId?: string
  private editTimeout?: ReturnType<typeof setTimeout>

  connect() {
    if (this.hasFormTarget) {
      this.inputTarget.id = `club_message_edit_${this.messageIdValue}`
      this.labelTarget.htmlFor = this.inputTarget.id
    }
    const latest = this.hasClubDiscussionOutlet ? this.clubDiscussionOutlet.latestMessageUpdate(this.messageIdValue) : undefined
    if (latest) this.displayUpdate(latest)
  }

  disconnect() {
    this.interruptSaving()
  }

  beforeCache() {
    this.finishSaving()
    this.bodyTarget.textContent = ""
    this.statusTarget.textContent = ""
    if (this.hasFormTarget) this.inputTarget.value = ""
  }

  edit() {
    if (!this.hasFormTarget || this.pendingEditId) return

    this.inputTarget.value = this.bodyTarget.textContent ?? ""
    this.formTarget.hidden = false
    this.bodyTarget.hidden = true
    this.editButtonTarget.hidden = true
    this.statusTarget.textContent = ""
    this.inputTarget.focus()
  }

  cancel() {
    if (this.pendingEditId) return

    this.inputTarget.value = ""
    this.closeEditor()
    this.statusTarget.textContent = ""
    this.editButtonTarget.focus()
  }

  async save(event: SubmitEvent) {
    event.preventDefault()
    if (this.pendingEditId) return
    if (!this.hasClubDiscussionOutlet) {
      this.statusTarget.textContent = "Live connection is not ready. Your draft is still here."
      return
    }

    const requestId = crypto.randomUUID()
    this.pendingEditId = requestId
    this.setSaving(true)
    this.statusTarget.textContent = "Saving…"
    try {
      const sent = await this.clubDiscussionOutlet.sendEdit(requestId, this.messageIdValue, this.inputTarget.value, this.element)
      if (this.pendingEditId !== requestId || !this.element.isConnected) return
      if (!sent) {
        this.interruptSaving()
        return
      }
      this.editTimeout = setTimeout(() => this.interruptSaving(), 20_000)
    } catch (error) {
      console.error("Failed to send discussion edit", error)
      if (this.pendingEditId === requestId) this.interruptSaving()
    }
  }

  receiveEdit(event: CustomEvent<DiscussionEvent>) {
    if (event.target !== this.element.closest("[data-controller~='club-discussion']")) return

    const result = event.detail
    if (result.type === "message.updated") {
      if (result.message) this.displayUpdate(result.message)
      return
    }
    if (!this.pendingEditId || result.request_id !== this.pendingEditId) return

    if (result.type === "edit.saved" && result.message?.id === this.messageIdValue) {
      this.displayUpdate(result.message)
      this.inputTarget.value = ""
      this.closeEditor()
      this.statusTarget.textContent = "Changes saved."
    } else if (result.type === "edit.rejected") {
      if (result.error === "forbidden") {
        this.statusTarget.textContent = "You do not have permission to edit. Your draft is still here."
      } else if (result.error === "not_found") {
        this.statusTarget.textContent = "This message is no longer available. Your draft is still here."
      } else {
        const errors = result.errors?.body?.join(", ")
        this.statusTarget.textContent = errors
          ? `Changes could not be saved: ${errors}. Your draft is still here.`
          : "Changes could not be saved. Your draft is still here."
      }
    } else {
      return
    }
    this.finishSaving()
  }

  connectionEnded(event: Event) {
    if (event.target === this.element.closest("[data-controller~='club-discussion']")) this.interruptSaving()
  }

  private displayUpdate(message: DiscussionMessage) {
    if (message.id !== this.messageIdValue || !Number.isFinite(Date.parse(message.updated_at))) return
    if (discussionVersion(message.updated_at) <= discussionVersion(this.updatedAtValue)) return

    this.updatedAtValue = message.updated_at
    const element = this.element as HTMLElement
    element.dataset.updatedAt = message.updated_at
    this.bodyTarget.textContent = message.body
    if (this.hasFormTarget && !this.formTarget.hidden && !this.pendingEditId) {
      this.statusTarget.textContent = "This message changed elsewhere. Your draft is still here."
    }
  }

  private closeEditor() {
    this.formTarget.hidden = true
    this.bodyTarget.hidden = false
    this.editButtonTarget.hidden = false
  }

  private interruptSaving() {
    if (this.pendingEditId) {
      this.statusTarget.textContent = "Changes could not be confirmed. Your draft is still here. Check the message before saving again."
    }
    this.finishSaving()
  }

  private finishSaving() {
    clearTimeout(this.editTimeout)
    this.editTimeout = undefined
    this.pendingEditId = undefined
    this.setSaving(false)
  }

  private setSaving(saving: boolean) {
    if (!this.hasFormTarget) return

    this.inputTarget.readOnly = saving
    this.saveTarget.disabled = saving
    this.cancelTarget.disabled = saving
  }
}
