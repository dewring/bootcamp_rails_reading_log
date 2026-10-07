import { Controller } from "@hotwired/stimulus"

export default class extends Controller<HTMLElement> {
  static targets = ["track", "viewport", "previous", "next"]
  static values = {
    pageSize: { type: Number, default: 5 },
    fitPage: { type: Boolean, default: false }
  }

  declare readonly trackTarget: HTMLElement
  declare readonly viewportTarget: HTMLElement
  declare readonly previousTarget: HTMLButtonElement
  declare readonly nextTarget: HTMLButtonElement
  declare readonly hasPreviousTarget: boolean
  declare readonly hasNextTarget: boolean
  declare readonly pageSizeValue: number
  declare readonly fitPageValue: boolean

  private index = 0
  private resizeObserver?: ResizeObserver

  connect(): void {
    this.resizeObserver = new ResizeObserver(() => this.update())
    this.resizeObserver.observe(this.viewportTarget)
    this.update()
  }

  disconnect(): void {
    this.resizeObserver?.disconnect()
  }

  previous(): void {
    this.index = Math.max(this.index - 1, 0)
    this.update()
  }

  next(): void {
    this.index = Math.min(this.index + 1, this.maximumIndex)
    this.update()
  }

  private get cards(): HTMLElement[] {
    return Array.from(this.trackTarget.children) as HTMLElement[]
  }

  private get maximumIndex(): number {
    const overflow = this.trackTarget.scrollWidth - this.viewportTarget.clientWidth
    const step = this.cardStep

    if (step <= 0) return Math.max(this.cards.length - this.pageSizeValue, 0)

    return Math.max(Math.ceil(Math.max(overflow, 0) / step), 0)
  }

  private get cardStep(): number {
    const card = this.cards[0]
    const gap = Number.parseFloat(getComputedStyle(this.trackTarget).columnGap) || 0

    return card ? card.getBoundingClientRect().width + gap : 0
  }

  private update(): void {
    this.fitCardsToViewport()

    const step = this.cardStep
    const overflow = Math.max(this.trackTarget.scrollWidth - this.viewportTarget.clientWidth, 0)
    const offset = this.index === this.maximumIndex ? overflow : this.index * step

    this.trackTarget.style.transform = `translateX(-${offset}px)`
    this.previousTarget.disabled = this.index === 0
    this.nextTarget.disabled = this.index === this.maximumIndex
  }

  private fitCardsToViewport(): void {
    if (!this.fitPageValue || this.viewportTarget.clientWidth <= 0) return

    const gap = Number.parseFloat(getComputedStyle(this.trackTarget).columnGap) || 0
    const cardWidth = (this.viewportTarget.clientWidth - gap * (this.pageSizeValue - 1)) / this.pageSizeValue

    if (cardWidth > 0) this.trackTarget.style.setProperty("--carousel-card-width", `${cardWidth}px`)
  }
}
