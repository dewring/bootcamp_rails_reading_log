import { Application } from "@hotwired/stimulus"
import { expect, test } from "vitest"
import LocalTimeController, { formatLocalTime } from "../../app/javascript/controllers/local_time_controller"

// Los Angeles keeps a stable rule (PST after Nov 1). Vancouver is avoided on
// purpose: BC moved to permanent UTC-7 in 2026 (tzdata 2026b), so its offset
// and abbreviation depend on which tzdata/ICU version the runtime ships.
test("a UTC timestamp is shown in the viewer's time zone", () => {
  const text = formatLocalTime("2026-11-12T01:00:00Z", "America/Los_Angeles")

  expect(text).toContain("Nov 11, 2026")
  expect(text).toContain("17:00")
  expect(text).toContain("PST")
})

test("an unreadable timestamp returns null so the server text is kept", () => {
  expect(formatLocalTime("not-a-time", "America/Los_Angeles")).toBeNull()
})

test("the controller replaces the UTC fallback text with the local time", async () => {
  document.body.innerHTML = '<time datetime="2026-11-12T01:00:00Z" data-controller="local-time">November 12, 2026 01:00 UTC</time>'
  const application = Application.start()
  application.register("local-time", LocalTimeController)

  await new Promise((resolve) => setTimeout(resolve, 0))

  const time = document.querySelector("time")!
  expect(time.textContent).toBe(formatLocalTime("2026-11-12T01:00:00Z"))
  application.stop()
})
