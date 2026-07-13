import { Controller } from "@hotwired/stimulus"

//class ProgressBarController < Controller
export default class extends Controller {
  //has_one :bar_target — the <div> we resize to show progress
  static targets = ["bar"]
  declare readonly barTarget: HTMLElement

  //attr_accessor :percent, backed by data-progress-bar-percent-value="..." in the HTML
  static values = { percent: { type: Number, default: 0 } }
  declare percentValue: number

  //def connect; render; end — runs once when the element appears in the DOM
  connect() {
    this.render()
  }

  //Stimulus calls this automatically whenever percentValue changes (e.g. after a Turbo Stream update)
  percentValueChanged() {
    this.render()
  }

  //private def render; bar_target.style.width = "#{clamp(percent)}%"; end
  private render(): void {
    const clamped = Math.max(0, Math.min(100, this.percentValue))
    this.barTarget.style.width = `${clamped}%`
    this.barTarget.setAttribute("aria-valuenow", String(clamped))
  }
}
