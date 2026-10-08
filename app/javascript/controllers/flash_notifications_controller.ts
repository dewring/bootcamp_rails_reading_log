import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  private header?: HTMLElement | null
  private headerObserver?: ResizeObserver
  private dismissTimer?: ReturnType<typeof setTimeout>

  connect() {
    this.header = document.querySelector<HTMLElement>(".nav-bar, .admin-topbar")
    if (this.header) {
      this.headerObserver = new ResizeObserver(() => this.position())
      this.headerObserver.observe(this.header)
    }
    this.position()
    this.dismissTimer = setTimeout(() => this.clear(), 5000)
  }

  disconnect() {
    this.headerObserver?.disconnect()
    clearTimeout(this.dismissTimer)
  }

  position() {
    const bottom = Math.max(0, this.header?.getBoundingClientRect().bottom ?? 0)
    this.element.style.top = `${bottom + 12}px`
  }

  dismiss(event: Event) {
    const button = event.currentTarget as HTMLElement
    button.closest(".flash-notification")?.remove()
    if (!this.element.querySelector(".flash-notification")) this.clear()
  }

  preserveDuringRefresh(event: Event) {
    event.preventDefault()
  }

  clear() {
    this.element.remove()
  }
}
