import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi, type Mock } from "vitest"
import ClubRepliesController from "../../app/javascript/controllers/club_replies_controller"
import ClubDiscussionController from "../../app/javascript/controllers/club_discussion_controller"
import type { DiscussionMessage } from "../../app/javascript/controllers/club_discussion_controller"

interface Subscription {
  unsubscribe(): void
  perform(action: string, data: { request_id: string; body: string; parent_id?: number }): boolean
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

async function mountReplyForm(ready = true) {
  element.id = "club_discussion_17"
  application.register("club-replies", ClubRepliesController)
  const controls = document.createElement("div")
  controls.dataset.controller = "club-replies"
  controls.dataset.clubRepliesPostIdValue = "1"
  controls.dataset.clubRepliesClubDiscussionOutlet = "#club_discussion_17"
  controls.dataset.action = "club-discussion:reply@document->club-replies#receiveReply club-discussion:connection-ended@document->club-replies#connectionEnded turbo:before-cache@document->club-replies#beforeCache"
  controls.innerHTML = `<button data-club-replies-target="toggle" aria-expanded="true" data-action="club-replies#toggle">Replies</button><div data-club-replies-target="panel"><div data-club-replies-target="list"></div><p data-club-replies-target="status"></p><button data-club-replies-target="more" hidden></button><form data-action="submit->club-replies#postReply"><label data-club-replies-target="label">Your reply</label><textarea data-club-replies-target="body"></textarea><button type="submit" data-club-replies-target="submit">Reply</button><button type="button" data-club-replies-target="cancel" data-action="club-replies#cancelReply">Cancel</button><p data-club-replies-target="composerStatus"></p></form></div>`
  messages.firstElementChild!.append(controls)
  await vi.waitFor(() => expect(controls.querySelector("label")!.htmlFor).toBe("club_reply_body_1"))
  if (ready) {
    completeSetup(requests[0])
    await requests[0].promise
    requests[0].callbacks.connected()
  }
  return {
    controls,
    form: controls.querySelector("form")!,
    body: controls.querySelector("textarea")!,
    submit: controls.querySelector<HTMLButtonElement>("[data-club-replies-target='submit']")!,
    cancel: controls.querySelector<HTMLButtonElement>("[data-club-replies-target='cancel']")!,
    notice: controls.querySelector<HTMLElement>("[data-club-replies-target='composerStatus']")!
  }
}

function replyEvent(id: number, type = "reply.created", requestId?: string) {
  const event = createdMessageEvent(id)
  event.type = type
  event.message.parent_id = 1
  return { ...event, request_id: requestId }
}

test("reply submission uses the existing Cable subscription and displays acknowledgement and broadcast only once", async () => {
  const composer = await mountReplyForm()
  const http = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("Writes must use Cable"))
  composer.body.value = "My answer"
  submitComposer(composer.form)
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const [action, data] = requests[0].perform.mock.calls[0]
  expect(action).toBe("post_reply")
  expect(data).toEqual({ request_id: expect.any(String), parent_id: 1, body: "My answer" })
  expect(composer.body.readOnly).toBe(true)
  expect(composer.cancel.disabled).toBe(true)
  requests[0].callbacks.received(replyEvent(8))
  requests[0].callbacks.received(replyEvent(8, "reply.saved", data.request_id))
  expect(composer.controls.querySelectorAll("#club_message_8")).toHaveLength(1)
  expect(composer.body.value).toBe("")
  expect(composer.notice.textContent).toBe("Reply published.")
  expect(composer.submit.disabled).toBe(false)
  expect(subscribeTo).toHaveBeenCalledOnce()
  expect(http).not.toHaveBeenCalled()
})

test.each([
  { error: "rate_limited", notice: "Too many posts or replies" },
  { error: "forbidden", notice: "permission to reply" },
  { error: "not_found", notice: "no longer available" },
  { errors: { body: ["can't be blank"] }, notice: "can't be blank" }
])("reply rejection preserves the draft: $notice", async result => {
  const composer = await mountReplyForm()
  composer.body.value = "Keep this answer"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]
  requests[0].callbacks.received({ type: "reply.rejected", request_id: data.request_id, ...result })
  expect(composer.body.value).toBe("Keep this answer")
  expect(composer.body.readOnly).toBe(false)
  expect(composer.notice.textContent).toContain(result.notice)
})

test("live replies are ordered chronologically and replies for another post are ignored", async () => {
  const composer = await mountReplyForm()
  requests[0].callbacks.received(replyEvent(10))
  requests[0].callbacks.received(replyEvent(8))
  requests[0].callbacks.received(replyEvent(10))
  const otherReply = replyEvent(11)
  otherReply.message.parent_id = 77
  requests[0].callbacks.received(otherReply)
  const ids = Array.from(composer.controls.querySelectorAll<HTMLElement>("article"), article => article.dataset.replyId)
  expect(ids).toEqual(["8", "10"])
  expect(postIds()).toEqual(["1"])
})

test("disconnecting while a reply is pending preserves its draft without retrying after reconnect", async () => {
  const composer = await mountReplyForm()
  composer.body.value = "Keep this answer"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  requests[0].callbacks.disconnected({ willAttemptReconnect: true })
  requests[0].callbacks.connected()
  expect(composer.body.value).toBe("Keep this answer")
  expect(composer.body.readOnly).toBe(false)
  expect(composer.notice.textContent).toContain("could not be confirmed")
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("missing reply acknowledgements preserve drafts and do not automatically retry", async () => {
  const composer = await mountReplyForm()
  vi.useFakeTimers()
  composer.body.value = "Keep this answer"
  submitComposer(composer.form)
  await vi.advanceTimersByTimeAsync(20_000)
  expect(composer.body.value).toBe("Keep this answer")
  expect(composer.notice.textContent).toContain("could not be confirmed")
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("a failed Cable send keeps the reply draft and permits a manual retry", async () => {
  const composer = await mountReplyForm()
  requests[0].perform.mockReturnValueOnce(false)
  composer.body.value = "Keep this answer"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(composer.notice.textContent).toContain("could not be confirmed"))
  expect(composer.body.value).toBe("Keep this answer")
  expect(composer.submit.disabled).toBe(false)
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("Turbo caching removes the reply form and clears its draft", async () => {
  const composer = await mountReplyForm()
  composer.body.value = "A private draft"
  document.dispatchEvent(new Event("turbo:before-cache"))
  expect(content.childElementCount).toBe(0)
  expect(composer.body.value).toBe("")
})

test("cancel clears the reply draft and collapses its panel", async () => {
  const composer = await mountReplyForm()
  composer.body.value = "An unwanted draft"
  composer.cancel.click()
  expect(composer.body.value).toBe("")
  expect(composer.controls.querySelector<HTMLElement>("[data-club-replies-target='panel']")!.hidden).toBe(true)
})

test("a reply form removed during subscription setup cannot send a late write", async () => {
  const composer = await mountReplyForm(false)
  requests[0].callbacks.connected()
  composer.body.value = "A detached answer"
  submitComposer(composer.form)
  composer.controls.remove()
  completeSetup(requests[0])
  await requests[0].promise
  await Promise.resolve()
  expect(requests[0].perform).not.toHaveBeenCalled()
})

test("live posts receive reply controls for their own reply history", async () => {
  const template = document.createElement("template")
  template.dataset.clubDiscussionTarget = "replyControls"
  template.innerHTML = `<div data-controller="club-replies"></div>`
  content.append(template)
  completeSetup(requests[0])
  await Promise.resolve()

  requests[0].callbacks.received(createdMessageEvent(2))

  const controls = messages.querySelector<HTMLElement>("#club_message_2 [data-controller='club-replies']")!
  expect(controls.dataset.clubRepliesPostIdValue).toBe("2")
  expect(controls.dataset.clubRepliesUrlValue).toBe("/book_clubs/17/club_messages/2/replies")
})

test("a reply access revocation event clears the enclosing private discussion", async () => {
  const controls = document.createElement("div")
  controls.dataset.action = "club-replies:access-revoked->club-discussion#endAccess"
  content.append(controls)
  completeSetup(requests[0])
  await Promise.resolve()
  await Promise.resolve()

  controls.dispatchEvent(new CustomEvent("club-replies:access-revoked", { bubbles: true }))

  expect(content.childElementCount).toBe(0)
  expect(status.textContent).toContain("Discussion access has ended")
})

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

test("rate limiting preserves the draft, unlocks the form, and does not retry", async () => {
  const composer = await mountComposer()
  composer.body.value = "Save this for later"
  submitComposer(composer.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]

  requests[0].callbacks.received({ type: "post.rejected", request_id: data.request_id, error: "rate_limited" })

  expect(composer.body.value).toBe("Save this for later")
  expect(composer.body.readOnly).toBe(false)
  expect(composer.submit.disabled).toBe(false)
  expect(composer.notice.textContent).toContain("Wait a minute")
  expect(requests[0].perform).toHaveBeenCalledOnce()
  expect(messages.textContent).toBe("Private discussion")
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

test("reply creation events do not insert replies into the top-level feed", () => {
  const event = createdMessageEvent(2)
  event.type = "reply.created"
  event.message.parent_id = 1

  requests[0].callbacks.received(event)

  expect(postIds()).toEqual(["1"])
})

test("older pages keep their history and display a notice for new posts", () => {
  element.setAttribute("data-club-discussion-page-value", "2")

  requests[0].callbacks.received(createdMessageEvent(22))

  expect(postIds()).toEqual(["1"])
  expect(messages.textContent).toBe("Private discussion")
  expect(status.textContent).toBe("New posts are available on the first page.")
})

function createdMessageEvent(id: number): { type: string; total_posts: number; message: DiscussionMessage } {
  return {
    type: "message.created",
    total_posts: id,
    message: {
      id,
      parent_id: null,
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
