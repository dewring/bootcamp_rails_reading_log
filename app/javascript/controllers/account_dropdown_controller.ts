import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  static targets = ["menu", "trigger"]

  declare readonly menuTarget: HTMLElement
  declare readonly triggerTarget: HTMLButtonElement

  private closeTimer?: number
  private hovering = false
  private focused = false

  disconnect() {
    this.cancelScheduledClose()
  }

  toggle() {
    if (this.hovering || this.focused) return

    this.isOpen() ? this.close() : this.open()
  }

  closeIfAnother(event: CustomEvent<{ source: HTMLElement }>) {
    if (event.detail?.source === this.element) return

    this.hovering = false
    this.focused = false
    this.close()
  }

  enter() {
    this.hovering = true
    this.cancelScheduledClose()
    this.open()
  }

  leave() {
    this.hovering = false
    this.scheduleClose()
  }

  focusIn() {
    this.focused = true
    this.cancelScheduledClose()
    this.open()
  }

  focusOut() {
    this.focused = false
    this.scheduleClose()
  }

  private open() {
    this.cancelScheduledClose()
    window.dispatchEvent(new CustomEvent("dropdown:opened", { detail: { source: this.element } }))
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  private close() {
    this.cancelScheduledClose()
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  private scheduleClose() {
    this.cancelScheduledClose()
    this.closeTimer = window.setTimeout(() => {
      if (!this.hovering && !this.focused) this.close()
    }, 150)
  }

  private cancelScheduledClose() {
    if (this.closeTimer === undefined) return

    window.clearTimeout(this.closeTimer)
    this.closeTimer = undefined
  }

  private isOpen(): boolean {
    return this.triggerTarget.getAttribute("aria-expanded") === "true"
  }

  closeOnOutsideClick(event: MouseEvent) {
    if (!this.element.contains(event.target as Node)) {
      this.close()
    }
  }

  closeOnEscape() {
    if (this.isOpen()) {
      this.close()
      this.triggerTarget.focus()
    }
  }
}
