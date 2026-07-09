//require "stimulus"
import { Controller } from "@hotwired/stimulus"
//require "some_gem"
import { debounce } from "lodash"

//class SearchController < Controller
export default class extends Controller {
  static targets = ["input"]
  //def initialize(delay: 300); @delay = delay; end
  static values = { delay: { type: Number, default: 300 } }

  declare readonly inputTarget: HTMLInputElement
  declare readonly delayValue: number

  //attr_accessor :debounced_submit
  private debouncedSubmit!: ReturnType<typeof debounce>

  //def initialize; @debounced_submit = ->(){ submit }; end
  initialize() {
    this.debouncedSubmit = debounce(() => this.submit(), this.delayValue)
    }

  //def query; @debounced_submit.call; end
  query() {
    this.debouncedSubmit()
  }

  //def before_destroy; @debounced_submit.cancel; end
  disconnect() {
    this.debouncedSubmit.cancel()
  }

  //private def submit; form = element.closest("form"); form&.request_submit; end
  private submit(): void {
    const form = this.element.closest("form")
    form?.requestSubmit()
  }
}