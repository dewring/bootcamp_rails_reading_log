import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  static targets = ["trigger", "menu", "value", "label", "option"]

  declare readonly triggerTarget: HTMLButtonElement
  declare readonly menuTarget: HTMLElement
  declare readonly valueTarget: HTMLInputElement
  declare readonly labelTarget: HTMLElement
  declare readonly optionTargets: HTMLButtonElement[]

  toggle() {
    this.isOpen() ? this.close() : this.open()
  }

  select(event: Event) {
    const option = event.currentTarget as HTMLButtonElement
    this.valueTarget.value = option.dataset.value ?? ""
    this.labelTarget.textContent = option.textContent?.trim() ?? ""

    this.optionTargets.forEach((candidate) => {
      const selected = candidate === option
      candidate.classList.toggle("is-selected", selected)
      candidate.setAttribute("aria-selected", String(selected))
    })

    this.close()
    this.triggerTarget.focus()
  }

  closeUnlessInside(event: Event) {
    if (!this.element.contains(event.target as Node)) this.close()
  }

  close() {
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  private open() {
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  private isOpen(): boolean {
    return this.triggerTarget.getAttribute("aria-expanded") === "true"
  }
}
