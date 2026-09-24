import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  static targets = ["menu", "trigger"]

  declare readonly menuTarget: HTMLElement
  declare readonly triggerTarget: HTMLButtonElement

  private boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
  private boundCloseOnEscape = this.closeOnEscape.bind(this)

  connect() {
    document.addEventListener("click", this.boundCloseOnOutsideClick)
    document.addEventListener("keydown", this.boundCloseOnEscape)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnOutsideClick)
    document.removeEventListener("keydown", this.boundCloseOnEscape)
  }

  toggle() {
    this.isOpen() ? this.close() : this.open()
  }

  private open() {
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  private close() {
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  private isOpen(): boolean {
    return this.triggerTarget.getAttribute("aria-expanded") === "true"
  }

  private closeOnOutsideClick(event: MouseEvent) {
    if (!this.element.contains(event.target as Node)) {
      this.close()
    }
  }

  private closeOnEscape(event: KeyboardEvent) {
    if (event.key === "Escape") {
      this.close()
      this.triggerTarget.focus()
    }
  }
}
