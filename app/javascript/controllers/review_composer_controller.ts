import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  static targets = ["closed", "composer", "form", "body", "counter", "ratingHint", "ratingStar"]

  declare readonly hasClosedTarget: boolean
  declare readonly closedTarget: HTMLElement
  declare readonly composerTarget: HTMLElement
  declare readonly formTarget: HTMLFormElement
  declare readonly bodyTarget: HTMLTextAreaElement
  declare readonly counterTarget: HTMLElement
  declare readonly ratingHintTarget: HTMLElement
  declare readonly ratingStarTargets: HTMLElement[]

  connect(): void {
    this.syncFormState()
  }

  open(): void {
    this.element.classList.add("is-editing")
    if (this.hasClosedTarget) this.closedTarget.hidden = true
    this.composerTarget.hidden = false
    this.syncFormState()
    this.bodyTarget.focus()
  }

  close(): void {
    this.element.classList.remove("is-editing")
    this.composerTarget.hidden = true
    if (this.hasClosedTarget) this.closedTarget.hidden = false
    this.formTarget.reset()
    this.syncFormState()
  }

  updateCount(): void {
    this.counterTarget.textContent = `${this.bodyTarget.value.length.toLocaleString()} / 2,000 characters`
  }

  updateRating(event: Event): void {
    const rating = Number((event.currentTarget as HTMLInputElement).value)
    this.setRating(rating)
  }

  private setRating(rating: number): void {
    this.ratingStarTargets.forEach((star, index) => {
      star.classList.toggle("is-selected", index < rating)
    })

    this.ratingHintTarget.textContent = rating > 0 ? `${rating} / 5` : "Select a rating"
  }

  private syncFormState(): void {
    this.updateCount()

    const selectedRating = this.formTarget.querySelector<HTMLInputElement>("input[name='review[rating]']:checked")
    this.setRating(selectedRating ? Number(selectedRating.value) : 0)
  }
}
