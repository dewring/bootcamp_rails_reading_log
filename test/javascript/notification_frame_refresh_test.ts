import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi } from "vitest"
import NotificationDropdownController from "../../app/javascript/controllers/notification_dropdown_controller"

const { subscribeTo } = vi.hoisted(() => ({ subscribeTo: vi.fn() }))
vi.mock("@hotwired/turbo-rails", () => ({ cable: { subscribeTo } }))
vi.mock("@hotwired/turbo", () => ({ renderStreamMessage: vi.fn() }))

let application: Application
let panel: HTMLElement
let controller: NotificationDropdownController
let unsubscribe: ReturnType<typeof vi.fn>

function frameContents(count: number) {
  return `<button data-notification-dropdown-target="trigger" aria-expanded="false">Notifications (${count})</button>
    <div data-notification-dropdown-target="menu" hidden><a href="/notifications">Refresh</a></div>`
}

beforeEach(async () => {
  unsubscribe = vi.fn()
  subscribeTo.mockReset()
  subscribeTo.mockResolvedValue({ unsubscribe })
  document.body.innerHTML = `<textarea>Unfinished discussion post</textarea>
    <ul><li data-controller="notification-dropdown">
      <turbo-frame id="notifications_frame">${frameContents(1)}</turbo-frame>
    </li></ul>`
  panel = document.querySelector("li")!
  application = Application.start()
  application.register("notification-dropdown", NotificationDropdownController)
  await vi.waitFor(() => {
    controller = application.getControllerForElementAndIdentifier(panel, "notification-dropdown") as NotificationDropdownController
    expect(controller).toBeTruthy()
    expect(subscribeTo).toHaveBeenCalledTimes(1)
  })
})

afterEach(async () => {
  document.body.innerHTML = ""
  await Promise.resolve()
  application.stop()
})

test("replacing notification frame contents preserves the open dropdown, draft, and existing subscription", async () => {
  controller.toggle()
  await vi.waitFor(() => expect(panel.querySelector<HTMLElement>("[data-notification-dropdown-target='menu']")!.hidden).toBe(false))

  panel.querySelector("turbo-frame")!.innerHTML = frameContents(2)

  await vi.waitFor(() => {
    expect(panel.querySelector<HTMLElement>("[data-notification-dropdown-target='menu']")!.hidden).toBe(false)
    expect(panel.querySelector("button")!.getAttribute("aria-expanded")).toBe("true")
  })
  expect(panel.querySelector("button")!.textContent).toBe("Notifications (2)")
  expect(document.querySelector("textarea")!.value).toBe("Unfinished discussion post")
  expect(subscribeTo).toHaveBeenCalledTimes(1)
  expect(unsubscribe).not.toHaveBeenCalled()
})

test("replacing notification frame contents keeps a closed dropdown closed", async () => {
  panel.querySelector("turbo-frame")!.innerHTML = frameContents(2)

  await vi.waitFor(() => {
    expect(panel.querySelector<HTMLElement>("[data-notification-dropdown-target='menu']")!.hidden).toBe(true)
    expect(panel.querySelector("button")!.getAttribute("aria-expanded")).toBe("false")
  })
  expect(subscribeTo).toHaveBeenCalledTimes(1)
})
