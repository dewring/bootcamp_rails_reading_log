import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi, type Mock } from "vitest"
import ClubDiscussionController from "../../app/javascript/controllers/club_discussion_controller"
import type { DiscussionMessage } from "../../app/javascript/controllers/club_discussion_controller"

interface Subscription {
  unsubscribe(): void
}

interface SubscriptionCallbacks {
  received(event: { type: string; message?: DiscussionMessage; total_posts?: number }): void
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
let messages: HTMLElement
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
  element.setAttribute("data-club-discussion-page-value", "1")
  element.setAttribute("data-club-discussion-total-posts-value", "1")
  element.setAttribute("data-action", "turbo:before-cache@document->club-discussion#beforeCache")
  element.innerHTML = `
    <section data-club-discussion-target="content"><div data-club-discussion-target="messages"><article id="club_message_1" data-message-id="1">Private discussion</article></div><p data-club-discussion-target="emptyState" hidden></p><p data-club-discussion-target="paginationSummary"></p><div data-club-discussion-target="pagination"></div><a data-club-discussion-target="olderPosts" href="/book_clubs/17/club_messages?page=2" hidden></a></section>
    <p data-club-discussion-target="status" role="status" hidden></p>
  `
  content = element.querySelector<HTMLElement>("[data-club-discussion-target='content']")!
  status = element.querySelector<HTMLElement>("[data-club-discussion-target='status']")!
  messages = element.querySelector<HTMLElement>("[data-club-discussion-target='messages']")!
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

test("new posts use text content for author and body and preserve timestamp precision", () => {
  const event = createdMessageEvent(2)
  event.message.author.nickname = "<img src=x onerror=alert(1)>"
  event.message.body = "<script>alert('post')</script>"

  requests[0].callbacks.received(event)

  const post = document.getElementById("club_message_2")!
  expect(post.tagName).toBe("ARTICLE")
  expect(post.querySelector("strong")?.textContent).toBe(event.message.author.nickname)
  expect(post.querySelector("p")?.textContent).toBe(event.message.body)
  expect(post.querySelector("img, script")).toBeNull()
  expect(post.querySelector("time")?.getAttribute("datetime")).toBe(event.message.created_at)
  expect(post.querySelector("time")?.textContent).toBe("Oct 17, 2026 · 09:45")
})

test("duplicate events and posts already in the HTML are ignored", () => {
  requests[0].callbacks.received(createdMessageEvent(1))
  const event = createdMessageEvent(2)
  requests[0].callbacks.received(event)
  event.message.body = "Duplicate content must not replace the first post"
  requests[0].callbacks.received(event)

  expect(postIds()).toEqual(["2", "1"])
  expect(document.getElementById("club_message_1")?.textContent).toBe("Private discussion")
  expect(document.querySelector("#club_message_2 p")?.textContent).toBe("Thought 2")
})

test("out-of-order creation events remain newest first and do not reduce the post total", () => {
  requests[0].callbacks.received(createdMessageEvent(4))
  requests[0].callbacks.received(createdMessageEvent(2))
  requests[0].callbacks.received(createdMessageEvent(3))

  expect(postIds()).toEqual(["4", "3", "2", "1"])
  expect(element.querySelector("[data-club-discussion-target='paginationSummary']")?.textContent)
    .toBe("4 posts · Page 1 of 1")
})

test("live history retains only the latest 20 posts and offers older history", () => {
  for (let id = 2; id <= 22; id += 1) {
    requests[0].callbacks.received(createdMessageEvent(id))
  }
  // A duplicate whose original element was removed must not be inserted again.
  requests[0].callbacks.received(createdMessageEvent(2))

  expect(messages.childElementCount).toBe(20)
  expect(postIds()[0]).toBe("22")
  expect(postIds()[19]).toBe("3")
  expect(element.querySelector("[data-club-discussion-target='paginationSummary']")?.textContent)
    .toBe("22 posts · Page 1 of 2")
  const olderPosts = element.querySelector<HTMLAnchorElement>("[data-club-discussion-target='olderPosts']")!
  expect(olderPosts.hidden).toBe(false)
  expect(olderPosts.getAttribute("href")).toContain("page=2")
})

test("the first live post hides the empty state", () => {
  messages.replaceChildren()
  const emptyState = element.querySelector<HTMLElement>("[data-club-discussion-target='emptyState']")!
  emptyState.hidden = false

  requests[0].callbacks.received(createdMessageEvent(2))

  expect(postIds()).toEqual(["2"])
  expect(emptyState.hidden).toBe(true)
})

test("older pages keep their history and display a notice for new posts", () => {
  element.setAttribute("data-club-discussion-page-value", "2")

  requests[0].callbacks.received(createdMessageEvent(22))

  expect(postIds()).toEqual(["1"])
  expect(messages.textContent).toBe("Private discussion")
  expect(status.textContent).toBe("New posts are available on the first page.")
})

function createdMessageEvent(id: number) {
  return {
    type: "message.created",
    total_posts: id,
    message: {
      id,
      body: `Thought ${id}`,
      author: { id: 7, nickname: "Reader" },
      created_at: "2026-10-17T09:45:12.123456Z",
      updated_at: "2026-10-17T09:45:12.123456Z"
    }
  }
}

function postIds() {
  return Array.from(messages.children, post => (post as HTMLElement).dataset.messageId)
}

async function removePage() {
  element.remove()
  await vi.waitFor(() => {
    expect(application.getControllerForElementAndIdentifier(element, "club-discussion")).toBeNull()
  })
}
