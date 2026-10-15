import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  static targets = ["menu", "trigger"]
  static values = { open: Boolean }

  declare openValue: boolean
  declare readonly menuTarget: HTMLElement
  declare readonly triggerTarget: HTMLButtonElement

  private closeTimer?: number
  private hovering = false
  private focused = false
  private restoringTriggerFocus = false

  disconnect() {
    this.cancelScheduledClose()
  }

  toggle() {
    this.openValue ? this.close() : this.open()
  }

  openValueChanged() {
    this.menuTarget.hidden = !this.openValue
    this.triggerTarget.setAttribute("aria-expanded", String(this.openValue))
  }

  closeIfAnother(event: CustomEvent<{ source: HTMLElement }>) {
    if (event.detail?.source === this.element) return

    this.hovering = false
    this.focused = false
    this.close()
  }

  enter() {
    this.hovering = true
    this.open()
  }

  leave() {
    this.hovering = false
    this.scheduleClose()
  }

  focusIn() {
    this.focused = true
    if (this.restoringTriggerFocus) {
      this.cancelScheduledClose()
      return
    }

    this.open()
  }

  focusOut() {
    this.focused = false
    this.scheduleClose()
  }

  private open() {
    this.cancelScheduledClose()
    this.dispatch("opened", { prefix: "dropdown", target: window, detail: { source: this.element } })
    this.openValue = true
  }

  private close() {
    this.cancelScheduledClose()
    this.openValue = false
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

  closeOnOutsideClick(event: MouseEvent) {
    if (!this.element.contains(event.target as Node)) {
      this.close()
    }
  }

  closeOnEscape() {
    if (this.openValue) {
      this.close()
      this.restoringTriggerFocus = true
      try {
        this.triggerTarget.focus()
      } finally {
        this.restoringTriggerFocus = false
      }
    }
  }
}
