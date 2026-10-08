import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  private headerObserver?: ResizeObserver

  connect() {
    const header = document.querySelector<HTMLElement>(".nav-bar, .admin-topbar")
    if (header) {
      this.headerObserver = new ResizeObserver(() => this.position())
      this.headerObserver.observe(header)
    }
    this.position()
  }

  disconnect() { this.headerObserver?.disconnect() }

  position() {
    const header = document.querySelector<HTMLElement>(".nav-bar, .admin-topbar")
    const bottom = Math.max(0, header?.getBoundingClientRect().bottom ?? 0)
    this.element.style.top = `${bottom + 12}px`
  }

  dismiss(event: Event) {
    const button = event.currentTarget as HTMLElement
    button.closest(".flash-notification")?.remove()
    if (!this.element.querySelector(".flash-notification")) this.clear()
  }

  clear() { this.element.remove() }
}
