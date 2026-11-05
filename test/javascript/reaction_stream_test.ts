import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi, type Mock, type MockInstance } from "vitest"

interface Subscription { unsubscribe(): void }
interface Callbacks {
  received(message: string): void
  connected(): void
  disconnected(details: { willAttemptReconnect: boolean }): void
  rejected(): void
}

const { subscribeTo, renderStreamMessage } = vi.hoisted(() => ({ subscribeTo: vi.fn(), renderStreamMessage: vi.fn() }))
vi.mock("@hotwired/turbo-rails", () => ({ cable: { subscribeTo } }))
vi.mock("@hotwired/turbo", () => ({ renderStreamMessage }))
import ReactionStreamController from "../../app/javascript/controllers/reaction_stream_controller"

let application: Application
let element: HTMLElement
let callbacks: Callbacks
let setup: ReturnType<typeof Promise.withResolvers<Subscription>>
let read: ReturnType<typeof Promise.withResolvers<Response>>
let unsubscribe: Mock<Subscription["unsubscribe"]>
let http: MockInstance<typeof fetch>

beforeEach(async () => {
  setup = Promise.withResolvers<Subscription>()
  read = Promise.withResolvers<Response>()
  unsubscribe = vi.fn<Subscription["unsubscribe"]>()
  subscribeTo.mockReset()
  renderStreamMessage.mockReset()
  subscribeTo.mockImplementation((_channel, handlers: Callbacks) => {
    callbacks = handlers
    return setup.promise
  })
  http = vi.spyOn(globalThis, "fetch").mockReturnValue(read.promise)
  vi.spyOn(console, "error").mockImplementation(() => {})
  element = document.createElement("main")
  element.dataset.controller = "reaction-stream"
  element.dataset.action = "turbo:frame-missing->reaction-stream#frameMissing turbo:fetch-request-error->reaction-stream#frameError"
  element.dataset.reactionStreamSignedStreamNameValue = "signed-public-book-stream"
  element.dataset.reactionStreamRefreshUrlValue = "/books/9"
  element.innerHTML = '<p role="status" data-reaction-stream-status></p><textarea>Unsent review draft</textarea><turbo-frame class="reaction-panel"></turbo-frame><turbo-frame class="reaction-panel"></turbo-frame>'
  document.body.append(element)
  application = Application.start()
  application.register("reaction-stream", ReactionStreamController)
  await vi.waitFor(() => expect(subscribeTo).toHaveBeenCalledOnce())
})

afterEach(async () => {
  element.remove()
  await Promise.resolve()
  setup.resolve({ unsubscribe })
  read.resolve(new Response("Late snapshot"))
  await Promise.allSettled([setup.promise, read.promise])
  application.stop()
  vi.useRealTimers()
})

async function live() {
  setup.resolve({ unsubscribe })
  await setup.promise
  callbacks.connected()
  read.resolve(new Response("Private frame snapshot"))
  await vi.waitFor(() => expect(renderStreamMessage).toHaveBeenCalledWith("Private frame snapshot"))
}

test("one signed public book subscription refreshes every panel through one uncached Turbo request", async () => {
  await live()

  expect(subscribeTo.mock.calls[0][0]).toEqual({ channel: "Turbo::StreamsChannel", signed_stream_name: "signed-public-book-stream" })
  expect(http).toHaveBeenCalledOnce()
  expect(http.mock.calls[0][0]).toBe("/books/9")
  expect(http.mock.calls[0][1]).toMatchObject({ headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin", cache: "no-store" })
  expect(element.querySelector("textarea")!.value).toBe("Unsent review draft")
})

test("live aggregate streams render without reloading private controls or making another request", async () => {
  await live()
  const control = document.createElement("button")
  control.setAttribute("aria-pressed", "true")
  element.append(control)
  const draft = element.querySelector("textarea")!

  callbacks.received('<turbo-stream action="replace" target="reaction_counts_book_9"></turbo-stream>')

  expect(renderStreamMessage).toHaveBeenLastCalledWith('<turbo-stream action="replace" target="reaction_counts_book_9"></turbo-stream>')
  expect(http).toHaveBeenCalledOnce()
  expect(element.querySelector("button[aria-pressed='true']")).toBe(control)
  expect(draft.value).toBe("Unsent review draft")
})

test("aggregate events received during refresh replay after the older private snapshot", async () => {
  callbacks.connected()
  callbacks.received("New aggregate counts")
  expect(renderStreamMessage).not.toHaveBeenCalled()

  read.resolve(new Response("Older frame snapshot"))

  await vi.waitFor(() => expect(renderStreamMessage).toHaveBeenCalledTimes(2))
  expect(renderStreamMessage.mock.calls.map(([html]) => html)).toEqual(["Older frame snapshot", "New aggregate counts"])
})

test("reconnection uses the existing subscription to refresh the current private panels", async () => {
  await live()
  callbacks.disconnected({ willAttemptReconnect: true })
  read = Promise.withResolvers<Response>()
  http.mockReturnValue(read.promise)
  callbacks.connected()
  read.resolve(new Response("Reconnected private snapshot"))

  await vi.waitFor(() => expect(renderStreamMessage).toHaveBeenLastCalledWith("Reconnected private snapshot"))
  expect(subscribeTo).toHaveBeenCalledOnce()
  expect(http).toHaveBeenCalledTimes(2)
})

test("a failed refresh reports the error preserves drafts and still applies buffered counts", async () => {
  callbacks.connected()
  callbacks.received("Valid aggregate counts")
  read.resolve(new Response("Unavailable", { status: 503 }))

  await vi.waitFor(() => expect(element.querySelector("[role='status']")!.textContent).toContain("could not refresh"))
  expect(renderStreamMessage).toHaveBeenCalledExactlyOnceWith("Valid aggregate counts")
  expect(element.querySelector("textarea")!.value).toBe("Unsent review draft")
})

test("disconnect cancels a pending refresh and a late response cannot render into another page", async () => {
  callbacks.connected()
  const signal = http.mock.calls[0][1]!.signal!
  element.remove()
  await Promise.resolve()

  expect(signal.aborted).toBe(true)
  read.resolve(new Response("Stale private snapshot"))
  await read.promise
  await Promise.resolve()
  expect(renderStreamMessage).not.toHaveBeenCalled()
})

test("disconnect releases a subscription that resolves after the page is removed exactly once", async () => {
  element.remove()
  await Promise.resolve()
  setup.resolve({ unsubscribe })

  await vi.waitFor(() => expect(unsubscribe).toHaveBeenCalledOnce())
  callbacks.connected()
  callbacks.received("Stale event")
  expect(http).not.toHaveBeenCalled()
  expect(renderStreamMessage).not.toHaveBeenCalled()
})

test("subscription setup rejection is reported and displayed", async () => {
  setup.reject(new Error("Subscription unavailable"))

  await vi.waitFor(() => expect(element.querySelector("[role='status']")!.textContent).toContain("could not connect"))
  expect(console.error).toHaveBeenCalled()
})

test("subscription rejection and cleanup failure are observable", async () => {
  unsubscribe.mockImplementation(() => { throw new Error("Cleanup failed") })
  setup.resolve({ unsubscribe })
  await setup.promise
  callbacks.rejected()
  expect(element.querySelector("[role='status']")!.textContent).toContain("could not connect")
  element.remove()

  await vi.waitFor(() => expect(console.error).toHaveBeenCalledWith("Failed to unsubscribe from book reactions", expect.any(Error)))
})

test("disconnect releases the refresh timeout even when the transport ignores cancellation", async () => {
  vi.useFakeTimers()
  callbacks.connected()
  expect(vi.getTimerCount()).toBe(1)
  element.remove()
  await Promise.resolve()

  expect(vi.getTimerCount()).toBe(0)
})

test("reconnecting before setup resolves cleans up the old subscription and ignores its callbacks", async () => {
  const oldSetup = setup
  const oldCallbacks = callbacks
  const oldUnsubscribe = unsubscribe
  element.dataset.controller = ""
  await Promise.resolve()
  setup = Promise.withResolvers<Subscription>()
  unsubscribe = vi.fn<Subscription["unsubscribe"]>()
  element.dataset.controller = "reaction-stream"
  await vi.waitFor(() => expect(subscribeTo).toHaveBeenCalledTimes(2))

  oldSetup.resolve({ unsubscribe: oldUnsubscribe })
  await vi.waitFor(() => expect(oldUnsubscribe).toHaveBeenCalledOnce())
  oldCallbacks.connected()
  oldCallbacks.received("Old stream message")
  expect(http).not.toHaveBeenCalled()
  expect(renderStreamMessage).not.toHaveBeenCalled()

  await live()
  expect(unsubscribe).not.toHaveBeenCalled()
})

test("a delayed response from the previous connection cannot overwrite the recovered snapshot", async () => {
  callbacks.connected()
  const oldRead = read
  callbacks.disconnected({ willAttemptReconnect: true })
  read = Promise.withResolvers<Response>()
  http.mockReturnValue(read.promise)
  callbacks.connected()
  read.resolve(new Response("Current snapshot"))
  await vi.waitFor(() => expect(renderStreamMessage).toHaveBeenCalledWith("Current snapshot"))

  oldRead.resolve(new Response("Stale snapshot"))
  await oldRead.promise
  await Promise.resolve()

  expect(renderStreamMessage).toHaveBeenCalledExactlyOnceWith("Current snapshot")
})

test("a stalled refresh times out visibly and releases its timer", async () => {
  vi.useFakeTimers()
  http.mockImplementation((_url, options) => new Promise<Response>((_resolve, reject) => {
    options!.signal!.addEventListener("abort", () => reject(new Error("Read aborted")), { once: true })
  }))
  callbacks.connected()

  await vi.advanceTimersByTimeAsync(10_000)

  expect(element.querySelector("[role='status']")!.textContent).toContain("could not refresh")
  expect(vi.getTimerCount()).toBe(0)
  expect(element.querySelector("textarea")!.value).toBe("Unsent review draft")
})

test("a throttled write retains the existing panel and draft and explains when to retry", () => {
  const frame = element.querySelector("turbo-frame")!
  frame.innerHTML = '<button aria-pressed="true">Like</button>'
  const button = frame.querySelector("button")
  const event = new CustomEvent("turbo:frame-missing", { bubbles: true, cancelable: true, detail: { response: new Response("Too many requests", { status: 429 }) } })

  frame.dispatchEvent(event)

  expect(event.defaultPrevented).toBe(true)
  expect(frame.querySelector("button")).toBe(button)
  expect(element.querySelector("[role='status']")!.textContent).toContain("Wait a minute")
  expect(element.querySelector("textarea")!.value).toBe("Unsent review draft")
})

test("an unconfirmed write reports its ambiguity without clearing controls or retrying the write", () => {
  const frame = element.querySelector("turbo-frame")!
  frame.innerHTML = '<form><button aria-pressed="true">Like</button></form>'
  frame.querySelector("form")!.dispatchEvent(new CustomEvent("turbo:fetch-request-error", { bubbles: true }))

  expect(element.querySelector("[role='status']")!.textContent).toContain("could not be confirmed")
  expect(frame.querySelector("button[aria-pressed='true']")).not.toBeNull()
  expect(http).not.toHaveBeenCalled()
})
