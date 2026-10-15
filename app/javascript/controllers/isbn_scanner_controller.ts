import { Controller } from "@hotwired/stimulus"
import { Html5Qrcode, Html5QrcodeSupportedFormats } from "html5-qrcode"

export default class extends Controller {
  static targets = ["viewport", "input", "status"]

  declare readonly viewportTarget: HTMLElement
  declare readonly inputTarget: HTMLInputElement
  declare readonly statusTarget: HTMLElement

  private scannerReady?: Promise<Html5Qrcode | undefined>
  private scannerStopped: Promise<void> = Promise.resolve()

  connect() {
    // Reconnection waits for the previous scanner to release the same viewport.
    const ready: Promise<Html5Qrcode | undefined> = this.scannerStopped
      .then(() => this.startScanner(ready))
      .catch(error => {
        console.error("Failed to start ISBN scanner", error)
        if (this.scannerReady === ready) {
          this.statusTarget.textContent = "Camera unavailable — enter the ISBN manually below."
        }
        return undefined
      })
    this.scannerReady = ready
  }

  disconnect() {
    this.stopScanner().catch(error => {
      console.error("Failed to stop ISBN scanner", error)
    })
  }

  private async startScanner(ready: Promise<Html5Qrcode | undefined>) {
    const scanner = new Html5Qrcode(this.viewportTarget.id, {
      formatsToSupport: [Html5QrcodeSupportedFormats.EAN_13],
      verbose: false,
    })

    await scanner.start(
      { facingMode: "environment" },
      { fps: 10, qrbox: { width: 250, height: 120 } },
      decodedText => {
        if (this.scannerReady !== ready) return

        this.onDecoded(decodedText).catch(error => {
          console.error("Failed to process scanned ISBN", error)
          if (this.element.isConnected) {
            this.statusTarget.textContent = "Camera could not stop — please try entering the ISBN manually."
          }
        })
      },
      () => {}
    )
    return scanner
  }

  private stopScanner(): Promise<void> {
    const ready = this.scannerReady
    this.scannerReady = undefined
    if (ready) {
      this.scannerStopped = ready.then(async scanner => {
        if (scanner?.isScanning) await scanner.stop()
      })
    }
    return this.scannerStopped
  }

  private async onDecoded(decodedText: string) {
    this.inputTarget.value = decodedText
    const form = this.inputTarget.closest("form")
    await this.stopScanner()
    if (this.element.isConnected && !this.scannerReady) form?.requestSubmit()
  }
}
