import { Controller } from "@hotwired/stimulus"

// Toggles a "condensed" class on the nav bar once the page scrolls past a
// small threshold, so the sticky header shrinks instead of staying full height.
//
// Uses two thresholds (enter/exit) instead of one so scroll positions that
// hover right at the boundary don't flip the class back and forth on every
// scroll event, which caused the header to visibly blink.
export default class extends Controller {
  static values = {
    enterThreshold: { type: Number, default: 40 },
    exitThreshold: { type: Number, default: 12 }
  }
  declare enterThresholdValue: number
  declare exitThresholdValue: number

  private boundOnScroll = this.onScroll.bind(this)

  connect() {
    window.addEventListener("scroll", this.boundOnScroll, { passive: true })
    this.onScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.boundOnScroll)
  }

  private onScroll(): void {
    const scrollY = window.scrollY
    if (scrollY > this.enterThresholdValue) {
      this.element.classList.add("is-condensed")
    } else if (scrollY <= this.exitThresholdValue) {
      this.element.classList.remove("is-condensed")
    }
  }
}
