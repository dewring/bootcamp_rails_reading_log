import { Controller } from "@hotwired/stimulus"

// Submits the controller's form as soon as its value changes, e.g. for a
// status <select> that should apply immediately without a separate button.
export default class extends Controller<HTMLElement> {
  submit(event: Event): void {
    const input = event.target
    if (input instanceof HTMLInputElement && input.type === "file" && !input.files?.length) return

    this.element.closest("form")?.requestSubmit()
  }
}
