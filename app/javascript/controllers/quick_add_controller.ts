import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit", "status"]

  declare readonly submitTarget: HTMLInputElement
  declare readonly statusTarget: HTMLElement

  submitting() {
    this.submitTarget.disabled = true
    this.statusTarget.hidden = false
  }

  done() {
    this.submitTarget.disabled = false
    this.statusTarget.hidden = true
  }
}
