// Keep fractional seconds when comparing UTC timestamps from Rails.
export function discussionVersion(timestamp: string): string {
  return timestamp.replace(/(?:\.(\d+))?Z$/, (_match, fraction: string = "") => `.${fraction.padEnd(6, "0")}Z`)
}
