import { Controller } from "@hotwired/stimulus"

const DISPLAY_FORMAT: Intl.DateTimeFormatOptions = {
  year: "numeric",
  month: "short",
  day: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
  timeZoneName: "short"
}

// The server keeps and renders times in UTC. Each viewer sees them in their
// own browser time zone; the server's UTC text stays as the no-JavaScript fallback.
export function formatLocalTime(isoTime: string, timeZone?: string): string | null {
  const time = new Date(isoTime)
  if (Number.isNaN(time.getTime())) return null

  return time.toLocaleString("en-US", { ...DISPLAY_FORMAT, timeZone })
}

export default class extends Controller<HTMLTimeElement> {
  connect(): void {
    const localText = formatLocalTime(this.element.dateTime)
    if (localText === null) return

    this.element.textContent = localText
  }
}
