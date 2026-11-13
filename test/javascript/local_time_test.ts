import { Application } from "@hotwired/stimulus"
import { expect, test } from "vitest"
import LocalTimeController, { formatLocalTime } from "../../app/javascript/controllers/local_time_controller"

test("a UTC timestamp is shown in the viewer's time zone", () => {
  const text = formatLocalTime("2026-11-12T01:00:00Z", "America/Vancouver")

  expect(text).toContain("Nov 11, 2026")
  expect(text).toContain("17:00")
  expect(text).toContain("PST")
})

test("an unreadable timestamp returns null so the server text is kept", () => {
  expect(formatLocalTime("not-a-time", "America/Vancouver")).toBeNull()
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
