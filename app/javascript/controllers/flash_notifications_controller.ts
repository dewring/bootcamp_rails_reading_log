import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  private headerObserver?: ResizeObserver
  private dismissTimer?: ReturnType<typeof setTimeout>

  connect() {
    const header = document.querySelector<HTMLElement>(".nav-bar, .admin-topbar")
    if (header) {
      this.headerObserver = new ResizeObserver(() => this.position())
      this.headerObserver.observe(header)
    }
    this.position()
    this.dismissTimer = setTimeout(() => this.clear(), 5000)
  }

  disconnect() {
    this.headerObserver?.disconnect()
    clearTimeout(this.dismissTimer)
  }

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

  clear() {
    clearTimeout(this.dismissTimer)
    this.element.remove()
  }
}
