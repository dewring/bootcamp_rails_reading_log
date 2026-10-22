import { Controller } from "@hotwired/stimulus"
import type ClubDiscussionController from "./club_discussion_controller"
import { discussionVersion, type DiscussionEvent, type DiscussionMessage } from "./club_discussion_controller"

export default class extends Controller {
  static targets = ["body", "form", "editButton", "input", "label", "save", "cancel", "status", "deleteButton"]
  static values = { messageId: Number, updatedAt: String }
  static outlets = ["club-discussion"]

  declare readonly messageIdValue: number
  declare updatedAtValue: string
  declare readonly bodyTarget: HTMLElement
  declare readonly hasFormTarget: boolean
  declare readonly formTarget: HTMLFormElement
  declare readonly hasEditButtonTarget: boolean
  declare readonly hasDeleteButtonTarget: boolean
  declare readonly deleteButtonTarget: HTMLButtonElement
  declare readonly editButtonTarget: HTMLButtonElement
  declare readonly inputTarget: HTMLTextAreaElement
  declare readonly labelTarget: HTMLLabelElement
  declare readonly saveTarget: HTMLButtonElement
  declare readonly cancelTarget: HTMLButtonElement
  declare readonly statusTarget: HTMLElement
  declare readonly hasClubDiscussionOutlet: boolean
  declare readonly clubDiscussionOutlet: ClubDiscussionController

  private pendingDeleteId?: string
  private deleteTimeout?: ReturnType<typeof setTimeout>
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
    this.interruptDeleting()
  }

  beforeCache() {
    this.finishDeleting()
    this.finishSaving()
    this.bodyTarget.textContent = ""
    this.statusTarget.textContent = ""
    if (this.hasFormTarget) this.inputTarget.value = ""
  }

  edit() {
    if (!this.hasFormTarget || this.pendingEditId || this.pendingDeleteId || this.isDeleted()) return

    this.inputTarget.value = this.bodyTarget.textContent ?? ""
    this.formTarget.hidden = false
    this.bodyTarget.hidden = true
    this.editButtonTarget.hidden = true
    this.statusTarget.textContent = ""
    this.inputTarget.focus()
  }

  cancel() {
    if (this.pendingEditId || this.pendingDeleteId || this.isDeleted()) return

    this.inputTarget.value = ""
    this.closeEditor()
    this.statusTarget.textContent = ""
    this.editButtonTarget.focus()
  }

  async save(event: SubmitEvent) {
    event.preventDefault()
    if (this.pendingEditId || this.pendingDeleteId || this.isDeleted()) return
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

  async deleteMessage() {
    if (this.pendingDeleteId || this.pendingEditId || this.isDeleted()) return
    if (!window.confirm("Delete this message? This cannot be undone.")) return
    if (!this.hasClubDiscussionOutlet) {
      this.statusTarget.textContent = "Live connection is not ready. The message has not been deleted."
      return
    }

    const requestId = crypto.randomUUID()
    this.pendingDeleteId = requestId
    this.deleteButtonTarget.disabled = true
    if (this.hasEditButtonTarget) this.editButtonTarget.disabled = true
    this.setSaving(true)
    this.statusTarget.textContent = "Deleting…"
    try {
      const sent = await this.clubDiscussionOutlet.sendDelete(requestId, this.messageIdValue, this.element)
      if (this.pendingDeleteId !== requestId || !this.element.isConnected) return
      if (!sent) {
        this.interruptDeleting()
        return
      }
      // A lost acknowledgement does not prove deletion failed; never retry automatically.
      this.deleteTimeout = setTimeout(() => this.interruptDeleting(), 5_000)
    } catch (error) {
      console.error("Failed to send discussion deletion", error)
      if (this.pendingDeleteId === requestId) this.interruptDeleting()
    }
  }

  receiveDelete(event: CustomEvent<DiscussionEvent>) {
    if (event.target !== this.element.closest("[data-controller~='club-discussion']")) return
    const result = event.detail
    if (!this.pendingDeleteId || result.request_id !== this.pendingDeleteId) return

    if (result.type === "delete.saved" && result.message?.id === this.messageIdValue) {
      this.displayUpdate(result.message)
    } else if (result.type === "delete.rejected") {
      this.statusTarget.textContent = result.error === "forbidden"
        ? "You do not have permission to delete this message."
        : "This message is no longer available. Refresh to check the discussion."
    } else {
      return
    }
    this.finishDeleting()
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
    if (event.target !== this.element.closest("[data-controller~='club-discussion']")) return

    this.interruptSaving()
    this.interruptDeleting()
  }

  private displayUpdate(message: DiscussionMessage) {
    if (message.id !== this.messageIdValue || !Number.isFinite(Date.parse(message.updated_at))) return
    if (this.isDeleted()) return
    if (discussionVersion(message.updated_at) < discussionVersion(this.updatedAtValue)) return
    if (discussionVersion(message.updated_at) === discussionVersion(this.updatedAtValue) && !message.deleted) return

    this.updatedAtValue = message.updated_at
    const element = this.element as HTMLElement
    element.dataset.updatedAt = message.updated_at
    if (message.deleted) {
      this.displayDeletion(message)
      return
    }
    this.bodyTarget.textContent = message.body
    if (this.hasFormTarget && !this.formTarget.hidden && !this.pendingEditId) {
      this.statusTarget.textContent = "This message changed elsewhere. Your draft is still here."
    }
  }

  private isDeleted() {
    return (this.element as HTMLElement).dataset.deleted === "true"
  }

  private displayDeletion(message: DiscussionMessage) {
    this.finishDeleting()
    this.finishSaving()
    if (this.hasFormTarget) {
      this.inputTarget.value = ""
      this.formTarget.remove()
    }
    if (this.hasEditButtonTarget) this.editButtonTarget.remove()
    if (this.hasDeleteButtonTarget) this.deleteButtonTarget.remove()
    const article = this.element as HTMLElement
    article.dataset.deleted = "true"
    this.statusTarget.textContent = ""
    if (message.parent_id !== null || message.replies_count === 0) {
      this.element.remove()
    } else {
      this.bodyTarget.hidden = false
      this.bodyTarget.textContent = "Deleted post"
    }
  }

  private interruptDeleting() {
    if (this.pendingDeleteId) {
      this.statusTarget.textContent = "Deletion could not be confirmed. Check the discussion before trying again."
    }
    this.finishDeleting()
  }

  private finishDeleting() {
    clearTimeout(this.deleteTimeout)
    this.deleteTimeout = undefined
    this.pendingDeleteId = undefined
    if (this.hasDeleteButtonTarget) this.deleteButtonTarget.disabled = false
    if (this.hasEditButtonTarget) this.editButtonTarget.disabled = false
    this.setSaving(false)
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
