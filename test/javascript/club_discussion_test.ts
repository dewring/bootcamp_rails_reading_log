import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi, type Mock } from "vitest"
import ClubDiscussionController from "../../app/javascript/controllers/club_discussion_controller"
import type { DiscussionMessage } from "../../app/javascript/controllers/club_discussion_controller"

interface Subscription {
  unsubscribe(): void
  perform(action: string, data: { request_id: string; body: string }): boolean
}

interface SubscriptionCallbacks {
  connected(): void
  received(event: { type: string; message?: DiscussionMessage; total_posts?: number; request_id?: string; errors?: { body?: string[] }; error?: string }): void
  rejected(): void
  disconnected(details: { willAttemptReconnect: boolean }): void
}

interface SubscriptionRequest {
  callbacks: SubscriptionCallbacks
  promise: Promise<Subscription>
  resolve(subscription: Subscription): void
  reject(error: Error): void
  unsubscribe: Mock<() => void>
  perform: Mock<Subscription["perform"]>
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
    requests.push({ callbacks, promise, resolve, reject, unsubscribe: vi.fn(), perform: vi.fn<Subscription["perform"]>().mockReturnValue(true) })
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
    request.resolve({ unsubscribe: request.unsubscribe, perform: request.perform })
  }
  await Promise.allSettled(requests.map(request => request.promise))
  application.stop()
  vi.useRealTimers()
})

async function mountComposer(confirmed = true) {
  const form = document.createElement("form")
  form.dataset.action = "submit->club-discussion#postMessage"
  form.innerHTML = `<textarea data-club-discussion-target="body"></textarea><button data-club-discussion-target="submit" disabled>Post</button><p role="status" data-club-discussion-target="composerStatus"></p>`
  content.append(form)
  completeSetup(requests[0])
  await Promise.resolve()
  if (confirmed) requests[0].callbacks.connected()
  return {
    form,
    body: form.querySelector("textarea")!,
    submit: form.querySelector("button")!,
    notice: form.querySelector("p")!
  }
}

function submitComposer(form: HTMLFormElement) {
  form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
}

function savedPostResult(requestId: string) {
  return { ...createdMessageEvent(2), type: "post.saved", request_id: requestId }
}

test("posting performs a Cable action and displays the saved result without an HTTP request", async () => {
  const composer = await mountComposer()
  const httpRequest = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("HTTP posting must not be used"))
  composer.body.value = "A new thought"

  submitComposer(composer.form)

  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const [action, data] = requests[0].perform.mock.calls[0]
  expect(action).toBe("post_message")
  expect(data).toEqual({ request_id: expect.any(String), body: "A new thought" })
  expect(composer.body.readOnly).toBe(true)
  expect(composer.submit.disabled).toBe(true)
  requests[0].callbacks.received(savedPostResult(data.request_id))

  expect(composer.notice.textContent).toBe("Post published.")
  expect(composer.body.value).toBe("")
  expect(composer.submit.disabled).toBe(false)
  expect(postIds()).toEqual(["2", "1"])
  expect(httpRequest).not.toHaveBeenCalled()
  requests[0].callbacks.received(createdMessageEvent(2))
  expect(postIds()).toEqual(["2", "1"])
})

test("pending Cable posting blocks duplicate submits and preserves drafts on validation rejection", async () => {
  const composer = await mountComposer()
  composer.body.value = "Keep this draft"

  submitComposer(composer.form)
  submitComposer(composer.form)

  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]
  requests[0].callbacks.received({ type: "post.rejected", request_id: data.request_id, errors: { body: ["is too long"] } })

  expect(composer.body.value).toBe("Keep this draft")
  expect(composer.body.readOnly).toBe(false)
  expect(composer.submit.disabled).toBe(false)
  expect(composer.notice.textContent).toContain("is too long")
})

test("a broadcast before acknowledgement does not clear the draft or duplicate the saved post", async () => {
  const composer = await mountComposer()
  composer.body.value = "Waiting for confirmation"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]

  requests[0].callbacks.received(createdMessageEvent(2))

  expect(composer.body.value).toBe("Waiting for confirmation")
  expect(composer.submit.disabled).toBe(true)
  requests[0].callbacks.received(savedPostResult(data.request_id))
  expect(postIds()).toEqual(["2", "1"])
  expect(composer.body.value).toBe("")
})

test("disconnection preserves the draft and reconnection never resends a post automatically", async () => {
  const composer = await mountComposer()
  composer.body.value = "Possibly saved"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const oldRequestId = requests[0].perform.mock.calls[0][1].request_id

  requests[0].callbacks.disconnected({ willAttemptReconnect: true })

  expect(composer.body.value).toBe("Possibly saved")
  expect(composer.body.readOnly).toBe(false)
  expect(composer.submit.disabled).toBe(true)
  expect(composer.notice.textContent).toContain("Check the discussion")
  requests[0].callbacks.connected()
  expect(composer.submit.disabled).toBe(false)
  expect(requests[0].perform).toHaveBeenCalledOnce()

  composer.body.value = "A newer draft"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledTimes(2))
  requests[0].callbacks.received(savedPostResult(oldRequestId))
  expect(composer.body.value).toBe("A newer draft")
  expect(composer.submit.disabled).toBe(true)
})

test("a failed Cable send preserves the draft and does not retry", async () => {
  const composer = await mountComposer()
  composer.body.value = "Not sent"
  requests[0].perform.mockReturnValue(false)

  submitComposer(composer.form)

  await vi.waitFor(() => expect(composer.notice.textContent).toContain("Check the discussion"))
  expect(composer.body.value).toBe("Not sent")
  expect(composer.body.readOnly).toBe(false)
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("a Cable send exception preserves the draft and reports the error", async () => {
  const composer = await mountComposer()
  composer.body.value = "Keep this"
  const error = new Error("Send failed")
  const errorLog = vi.spyOn(console, "error").mockImplementation(() => {})
  requests[0].perform.mockImplementation(() => { throw error })

  submitComposer(composer.form)

  await vi.waitFor(() => expect(errorLog).toHaveBeenCalledWith("Failed to send discussion post", error))
  expect(composer.body.value).toBe("Keep this")
  expect(composer.body.readOnly).toBe(false)
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("a missing acknowledgement unlocks the draft after 20 seconds without retrying", async () => {
  const composer = await mountComposer()
  composer.body.value = "Unconfirmed"
  vi.useFakeTimers()

  submitComposer(composer.form)
  await Promise.resolve()
  await vi.advanceTimersByTimeAsync(20_000)

  expect(composer.body.value).toBe("Unconfirmed")
  expect(composer.body.readOnly).toBe(false)
  expect(composer.notice.textContent).toContain("Check the discussion")
  expect(requests[0].perform).toHaveBeenCalledOnce()
  vi.useRealTimers()
})

test("posting waits for subscription confirmation before sending", async () => {
  const composer = await mountComposer(false)
  composer.body.value = "Wait for Cable"

  submitComposer(composer.form)

  expect(requests[0].perform).not.toHaveBeenCalled()
  expect(composer.body.value).toBe("Wait for Cable")
  expect(composer.notice.textContent).toContain("not ready")
  expect(composer.submit.disabled).toBe(true)
})

test("Turbo caching cancels a pending send before subscription setup resumes", async () => {
  const composer = await mountComposer()
  submitComposer(composer.form)

  document.dispatchEvent(new Event("turbo:before-cache"))
  await Promise.resolve()

  expect(content.textContent).toBe("")
  expect(requests[0].perform).not.toHaveBeenCalled()
})

test("forbidden posting preserves the draft and existing readable history", async () => {
  const composer = await mountComposer()
  composer.body.value = "Not permitted"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]

  requests[0].callbacks.received({ type: "post.rejected", request_id: data.request_id, error: "forbidden" })

  expect(messages.textContent).toBe("Private discussion")
  expect(composer.body.value).toBe("Not permitted")
  expect(composer.notice.textContent).toContain("permission")
})

test("late posting results cannot restore private content after access is revoked", async () => {
  const composer = await mountComposer()
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]

  requests[0].callbacks.received({ type: "access.revoked" })
  requests[0].callbacks.received(savedPostResult(data.request_id))

  expect(content.textContent).toBe("")
  expect(document.getElementById("club_message_2")).toBeNull()
})

function completeSetup(request: SubscriptionRequest) {
  request.resolve({ unsubscribe: request.unsubscribe, perform: request.perform })
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
