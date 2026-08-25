import { Controller } from "@hotwired/stimulus"
import { debounce } from "lodash"

interface BookResult {
  id: number
  title: string
}

export default class extends Controller {
  static targets = ["search", "hidden", "options"]
  static values = { delay: { type: Number, default: 300 } }

  declare readonly searchTarget: HTMLInputElement
  declare readonly hiddenTarget: HTMLInputElement
  declare readonly optionsTarget: HTMLDataListElement
  declare readonly delayValue: number

  private debouncedFetchMatches!: ReturnType<typeof debounce>

  initialize() {
    this.debouncedFetchMatches = debounce(() => this.fetchMatches(), this.delayValue)
  }

  disconnect() {
    this.debouncedFetchMatches.cancel()
  }

  input() {
    this.syncHidden()
    this.debouncedFetchMatches()
  }

  private syncHidden() {
    const options = Array.from(this.optionsTarget.options)
    const match = options.find((option) => option.value === this.searchTarget.value)

    this.hiddenTarget.value = match?.dataset.id ?? ""
  }

  private async fetchMatches() {
    const query = this.searchTarget.value.trim()

    if (query === "") {
      this.optionsTarget.replaceChildren()
      return
    }

    const response = await fetch(`/books.json?q=${encodeURIComponent(query)}`)
    if (!response.ok) return

    const { books }: { books: BookResult[] } = await response.json()

    this.optionsTarget.replaceChildren(
      ...books.map((book) => {
        const option = document.createElement("option")
        option.value = book.title
        option.dataset.id = String(book.id)
        return option
      })
    )

    this.syncHidden()
  }
}
