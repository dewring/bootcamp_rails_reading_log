import { Controller } from "@hotwired/stimulus"

// Submits the controller's form as soon as its value changes, e.g. for a
// status <select> that should apply immediately without a separate button.
export default class extends Controller {
  submit(): void {
    (this.element as HTMLElement).closest("form")?.requestSubmit()
  }
}
