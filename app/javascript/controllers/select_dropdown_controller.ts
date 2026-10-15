import { Controller, type ActionEvent } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  static targets = ["trigger", "menu", "value", "label", "option"]
  static values = { open: Boolean }

  declare openValue: boolean
  declare readonly triggerTarget: HTMLButtonElement
  declare readonly menuTarget: HTMLElement
  declare readonly valueTarget: HTMLInputElement
  declare readonly labelTarget: HTMLElement
  declare readonly optionTargets: HTMLButtonElement[]

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged() {
    this.menuTarget.hidden = !this.openValue
    this.triggerTarget.setAttribute("aria-expanded", String(this.openValue))
  }

  select(event: ActionEvent) {
    const option = event.currentTarget as HTMLButtonElement
    this.valueTarget.value = String(event.params.value ?? "")
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
    this.openValue = false
  }
}
