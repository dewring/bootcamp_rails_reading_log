import { Controller } from "@hotwired/stimulus"

// Toggles a "condensed" class on the nav bar once the page scrolls past a
// small threshold, so the sticky header shrinks instead of staying full height.
export default class extends Controller {
  static values = { threshold: { type: Number, default: 12 } }
  declare thresholdValue: number

  private boundOnScroll = this.onScroll.bind(this)

  connect() {
    window.addEventListener("scroll", this.boundOnScroll, { passive: true })
    this.onScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.boundOnScroll)
  }

  private onScroll(): void {
    this.element.classList.toggle("is-condensed", window.scrollY > this.thresholdValue)
  }
}
