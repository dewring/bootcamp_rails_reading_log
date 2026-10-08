import { Controller } from "@hotwired/stimulus"

interface BookMatch { id: number; title: string; author: string }

export default class extends Controller<HTMLElement> {
  static targets = ["search", "value", "results", "status"]
  static values = { url: String }
  declare readonly searchTarget: HTMLInputElement
  declare readonly valueTarget: HTMLInputElement
  declare readonly resultsTarget: HTMLElement
  declare readonly statusTarget: HTMLElement
  declare readonly urlValue: string
  private timer?: ReturnType<typeof setTimeout>
  private request?: AbortController
  private matches: BookMatch[] = []
  private activeIndex = -1
  private selectedLabel = ""
  private selectedId = ""

  connect() { this.selectedLabel = this.searchTarget.value; this.selectedId = this.valueTarget.value }
  disconnect() { clearTimeout(this.timer); this.request?.abort() }

  search() {
    clearTimeout(this.timer)
    this.request?.abort()
    this.close()
    const query = this.searchTarget.value.trim()
    if (this.searchTarget.value === this.selectedLabel) {
      this.valueTarget.value = this.selectedId
      this.searchTarget.setCustomValidity("")
      return
    }
    this.valueTarget.value = ""
    this.searchTarget.setCustomValidity(query ? "Choose a book from the search results, or clear this field for no current pick." : "")
    if (!query) { this.selectedLabel = ""; this.selectedId = ""; this.statusTarget.textContent = "No current pick"; return }
    this.statusTarget.textContent = "Searching books…"
    this.timer = setTimeout(() => { void this.fetchMatches(query) }, 300)
  }

  closeUnlessInside(event: Event) {
    if (!this.element.contains(event.target as Node)) this.close()
  }

  close(event?: Event) {
    clearTimeout(this.timer)
    this.request?.abort()
    event?.preventDefault()
    this.resultsTarget.hidden = true
    this.searchTarget.setAttribute("aria-expanded", "false")
    this.searchTarget.removeAttribute("aria-activedescendant")
    this.activeIndex = -1
  }

  next(event: Event) { this.move(event, 1) }
  previous(event: Event) { this.move(event, -1) }
  choose(event: Event) {
    event.preventDefault()
    if (!this.resultsTarget.hidden && this.activeIndex >= 0) this.selectMatch(this.activeIndex)
  }
  select(event: Event) {
    this.selectMatch(Number((event.currentTarget as HTMLElement).dataset.index))
  }

  private selectMatch(index: number) {
    const book = this.matches[index]
    if (!book) return
    this.selectedLabel = `${book.title} · ${book.author}`
    this.searchTarget.value = this.selectedLabel
    this.valueTarget.value = String(book.id)
    this.selectedId = String(book.id)
    this.searchTarget.setCustomValidity("")
    this.statusTarget.textContent = `Selected ${this.selectedLabel}`
    this.close()
    this.searchTarget.focus()
  }

  private move(event: Event, direction: number) {
    event.preventDefault()
    if (this.resultsTarget.hidden || !this.matches.length) return
    this.activeIndex = this.activeIndex < 0 ? (direction > 0 ? 0 : this.matches.length - 1) : (this.activeIndex + direction + this.matches.length) % this.matches.length
    Array.from(this.resultsTarget.children).forEach((option, index) => {
      option.setAttribute("aria-selected", String(index === this.activeIndex))
      option.classList.toggle("is-selected", index === this.activeIndex)
    })
    const option = this.resultsTarget.children[this.activeIndex] as HTMLElement
    this.searchTarget.setAttribute("aria-activedescendant", option.id)
    option.scrollIntoView({ block: "nearest" })
  }

  private async fetchMatches(query: string) {
    const request = new AbortController()
    this.request = request
    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, { signal: request.signal, headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("Book search failed")
      const data: { books: BookMatch[] } = await response.json()
      if (request.signal.aborted || this.searchTarget.value.trim() !== query) return
      this.matches = data.books
      this.resultsTarget.replaceChildren(...this.matches.map((book, index) => {
        const option = document.createElement("button")
        option.type = "button"
        option.id = `admin-club-book-option-${book.id}`
        option.className = "catalog-dropdown-option"
        option.textContent = `${book.title} · ${book.author}`
        option.dataset.index = String(index)
        option.dataset.action = "click->club-book-search#select"
        option.setAttribute("role", "option")
        option.setAttribute("aria-selected", "false")
        option.tabIndex = -1
        return option
      }))
      if (!this.matches.length) {
        const message = document.createElement("p")
        message.textContent = "No matching books. Try another title or author."
        this.resultsTarget.append(message)
      }
      this.statusTarget.textContent = `${this.matches.length} matching books`
      this.resultsTarget.hidden = false
      this.searchTarget.setAttribute("aria-expanded", "true")
    } catch {
      if (!request.signal.aborted) {
        const message = document.createElement("p")
        message.textContent = "Book search could not load. Please try again."
        this.resultsTarget.replaceChildren(message)
        this.matches = []
        this.resultsTarget.hidden = false
        this.searchTarget.setAttribute("aria-expanded", "true")
        this.statusTarget.textContent = message.textContent
      }
    }
  }
}
