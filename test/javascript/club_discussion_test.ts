import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi, type Mock } from "vitest"
import ClubDiscussionController from "../../app/javascript/controllers/club_discussion_controller"

interface Subscription {
  unsubscribe(): void
}

interface SubscriptionCallbacks {
  received(event: { type: string }): void
  rejected(): void
  disconnected(details: { willAttemptReconnect: boolean }): void
}

interface SubscriptionRequest {
  callbacks: SubscriptionCallbacks
  promise: Promise<Subscription>
  resolve(subscription: Subscription): void
  reject(error: Error): void
  unsubscribe: Mock<() => void>
}

type SubscribeTo = (
  channel: { channel: string; book_club_id: number },
  callbacks: SubscriptionCallbacks
) => Promise<Subscription>

// Replace the network boundary, leaving Stimulus and the controller running normally.
const { subscribeTo } = vi.hoisted(() => ({ subscribeTo: vi.fn<SubscribeTo>() }))
vi.mock("@hotwired/turbo-rails", () => ({ cable: { subscribeTo } }))

let application: Application
let element: HTMLDivElement
let content: HTMLElement
let status: HTMLElement
let requests: SubscriptionRequest[]

beforeEach(async () => {
  requests = []
  subscribeTo.mockImplementation((_channel, callbacks) => {
    const { promise, resolve, reject } = Promise.withResolvers<Subscription>()
    requests.push({ callbacks, promise, resolve, reject, unsubscribe: vi.fn() })
    return promise
  })

  element = document.createElement("div")
  element.setAttribute("data-controller", "club-discussion")
  element.setAttribute("data-club-discussion-book-club-id-value", "17")
  element.setAttribute("data-action", "turbo:before-cache@document->club-discussion#beforeCache")
  element.innerHTML = `
    <section data-club-discussion-target="content">Private discussion</section>
    <p data-club-discussion-target="status" role="status" hidden></p>
  `
  content = element.querySelector<HTMLElement>("[data-club-discussion-target='content']")!
  status = element.querySelector<HTMLElement>("[data-club-discussion-target='status']")!
  document.body.append(element)

  application = Application.start()
  application.register("club-discussion", ClubDiscussionController)
  await vi.waitFor(() => expect(subscribeTo).toHaveBeenCalledOnce())
})

afterEach(async () => {
  await removePage()
  for (const request of requests) {
    request.resolve({ unsubscribe: request.unsubscribe })
  }
  await Promise.allSettled(requests.map(request => request.promise))
  application.stop()
})

function completeSetup(request: SubscriptionRequest) {
  request.resolve({ unsubscribe: request.unsubscribe })
}

test("subscribes to the club identified by the page HTML", () => {
  expect(subscribeTo).toHaveBeenCalledWith(
    { channel: "ClubDiscussionChannel", book_club_id: 17 },
    expect.any(Object)
  )
  completeSetup(requests[0])
  expect(content.textContent).toBe("Private discussion")
})

test("revocation clears private content, displays a notice, and unsubscribes", async () => {
  completeSetup(requests[0])

  requests[0].callbacks.received({ type: "access.revoked" })

  expect(content.textContent).toBe("")
  expect(status.hidden).toBe(false)
  expect(status.textContent).toContain("access has ended")
  await vi.waitFor(() => expect(requests[0].unsubscribe).toHaveBeenCalledOnce())
})

test("removing the page unsubscribes even when setup finishes later", async () => {
  await removePage()

  completeSetup(requests[0])

  await vi.waitFor(() => expect(requests[0].unsubscribe).toHaveBeenCalledOnce())
})

test("old subscriptions cannot clear content after the page reconnects", async () => {
  await removePage()
  document.body.append(element)
  await vi.waitFor(() => expect(subscribeTo).toHaveBeenCalledTimes(2))

  completeSetup(requests[1])
  completeSetup(requests[0])
  await vi.waitFor(() => expect(requests[0].unsubscribe).toHaveBeenCalledOnce())
  requests[0].callbacks.received({ type: "access.revoked" })

  expect(content.textContent).toBe("Private discussion")
  expect(requests[1].unsubscribe).not.toHaveBeenCalled()
})

test("Turbo's before-cache event clears content and releases pending setup", async () => {
  document.dispatchEvent(new Event("turbo:before-cache"))
  completeSetup(requests[0])

  expect(content.textContent).toBe("")
  await vi.waitFor(() => expect(requests[0].unsubscribe).toHaveBeenCalledOnce())
})

test("temporary disconnection preserves content but permanent disconnection clears it", async () => {
  completeSetup(requests[0])

  requests[0].callbacks.disconnected({ willAttemptReconnect: true })
  expect(content.textContent).toBe("Private discussion")

  requests[0].callbacks.disconnected({ willAttemptReconnect: false })
  expect(content.textContent).toBe("")
  await vi.waitFor(() => expect(requests[0].unsubscribe).toHaveBeenCalledOnce())
})

test("subscription rejection clears content and releases pending setup", async () => {
  requests[0].callbacks.rejected()
  completeSetup(requests[0])

  expect(content.textContent).toBe("")
  await vi.waitFor(() => expect(requests[0].unsubscribe).toHaveBeenCalledOnce())
})

test("setup failure displays a notice and preserves existing history", async () => {
  const errorLog = vi.spyOn(console, "error").mockImplementation(() => {})
  const error = new Error("Connection failed")

  requests[0].reject(error)

  await vi.waitFor(() => expect(status.textContent).toContain("could not connect"))
  expect(content.textContent).toBe("Private discussion")
  expect(errorLog).toHaveBeenCalledWith("Failed to subscribe to club discussion", error)
})

test("unsubscribe failure is reported after private content is cleared", async () => {
  const errorLog = vi.spyOn(console, "error").mockImplementation(() => {})
  const error = new Error("Cleanup failed")
  requests[0].unsubscribe.mockImplementation(() => { throw error })
  completeSetup(requests[0])

  requests[0].callbacks.received({ type: "access.revoked" })

  expect(content.textContent).toBe("")
  await vi.waitFor(() => {
    expect(errorLog).toHaveBeenCalledWith("Failed to unsubscribe from club discussion", error)
  })
})

async function removePage() {
  element.remove()
  await vi.waitFor(() => {
    expect(application.getControllerForElementAndIdentifier(element, "club-discussion")).toBeNull()
  })
}
