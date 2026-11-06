import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["counts", "pill", "picker"]
  declare readonly pillTargets: HTMLElement[]
  declare readonly pickerTarget: HTMLDetailsElement
  declare readonly hasPickerTarget: boolean

  // Public broadcasts replace only this snapshot, never the viewer's forms.
  countsTargetConnected(counts: HTMLElement) {
    const totals = new Map(Array.from(counts.querySelectorAll<HTMLElement>("[data-reaction-kind]"))
      .map(item => [item.dataset.reactionKind, Number(item.dataset.count)]))
    for (const pill of this.pillTargets) {
      const count = totals.get(pill.dataset.kind) ?? 0
      pill.hidden = count === 0 && pill.dataset.selected !== "true"
      pill.querySelector<HTMLElement>("[data-reaction-pill-count]")!.textContent = String(count)
      pill.querySelector<HTMLElement>(".reaction-pill")!.setAttribute("aria-label", `${pill.dataset.label}: ${count}`)
    }
  }

  closeOutside(event: MouseEvent) {
    if (!this.element.contains(event.target as Node)) this.close()
  }

  close(event?: KeyboardEvent) {
    if (!this.hasPickerTarget || !this.pickerTarget.open) return

    this.pickerTarget.open = false
    if (event) this.pickerTarget.querySelector("summary")!.focus()
  }
}
