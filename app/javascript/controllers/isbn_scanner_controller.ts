import { Controller } from "@hotwired/stimulus"
import { Html5Qrcode, Html5QrcodeSupportedFormats } from "html5-qrcode"

export default class extends Controller {
  static targets = ["viewport", "input", "status"]

  declare readonly viewportTarget: HTMLElement
  declare readonly inputTarget: HTMLInputElement
  declare readonly statusTarget: HTMLElement

  private scanner: Html5Qrcode | null = null

  connect() {
    this.start()
  }

  disconnect() {
    this.stop()
  }

  private async start() {
    this.scanner = new Html5Qrcode(this.viewportTarget.id, {
      formatsToSupport: [Html5QrcodeSupportedFormats.EAN_13],
      verbose: false,
    })

    try {
      await this.scanner.start(
        { facingMode: "environment" },
        { fps: 10, qrbox: { width: 250, height: 120 } },
        (decodedText) => this.onDecoded(decodedText),
        () => {}
      )
    } catch {
      this.statusTarget.textContent = "Camera unavailable — enter the ISBN manually below."
    }
  }

  private async stop() {
    if (this.scanner?.isScanning) {
      await this.scanner.stop()
    }
  }

  private onDecoded(decodedText: string) {
    this.inputTarget.value = decodedText
    this.stop()
    this.inputTarget.closest("form")?.requestSubmit()
  }
}
