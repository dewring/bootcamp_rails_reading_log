import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]

  declare readonly messageTarget: HTMLSpanElement

  connect() {
    this.messageTarget.textContent = "Welcome back, reader!"
  }

  greet() {
    this.messageTarget.textContent = "Keep up the great reading streak!"
  }
}
