import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLFormElement> {
  static targets = ["file"]

  declare readonly fileTarget: HTMLInputElement

  submit(): void {
    if (this.fileTarget.files?.length) this.element.requestSubmit()
  }
}
