import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi, type MockInstance } from "vitest"
import ClubDiscussionController from "../../app/javascript/controllers/club_discussion_controller"
import type { DiscussionEvent, DiscussionMessage } from "../../app/javascript/club_discussion/types"
import ClubMessageController from "../../app/javascript/controllers/club_message_controller"

interface Callbacks {
  connected(): void
  disconnected(details: { willAttemptReconnect: boolean }): void
  received(event: DiscussionEvent): void
  rejected(): void
}

const { subscribeTo } = vi.hoisted(() => ({ subscribeTo: vi.fn() }))
vi.mock("@hotwired/turbo-rails", () => ({ cable: { subscribeTo } }))

let application: Application
let element: HTMLElement
let callbacks: Callbacks
let read: ReturnType<typeof Promise.withResolvers<Response>>
let http: MockInstance<typeof fetch>
let unsubscribe: ReturnType<typeof vi.fn>
let perform: ReturnType<typeof vi.fn>

function post(id: number, overrides: Partial<DiscussionMessage> = {}): DiscussionMessage {
  return {
    id, parent_id: null, body: `Thought ${id}`, replies_count: 0, deleted: false,
    author: { id: 7, nickname: "Reader" },
    created_at: "2026-10-21T12:00:00.000001Z",
    updated_at: "2026-10-21T12:00:00.000001Z",
    ...overrides
  }
}

function snapshot(posts: DiscussionMessage[], total = posts.length) {
  return new Response(JSON.stringify({ messages: posts, total_posts: total, pagination_html: "" }))
}

function ids() {
  return Array.from(element.querySelectorAll<HTMLElement>("[data-club-discussion-target='messages'] > article"), article => Number(article.dataset.messageId))
}

function state() {
  return element.dataset.connectionState
}

async function connect() {
  await Promise.resolve()
  callbacks.connected()
}

async function finish(posts: DiscussionMessage[], total = posts.length) {
  read.resolve(snapshot(posts, total))
  await vi.waitFor(() => expect(state()).toBe("live"))
}

beforeEach(async () => {
  unsubscribe = vi.fn()
  perform = vi.fn().mockReturnValue(true)
  subscribeTo.mockImplementation((_channel, handlers: Callbacks) => {
    callbacks = handlers
    return Promise.resolve({ unsubscribe, perform })
  })
  read = Promise.withResolvers<Response>()
  http = vi.spyOn(globalThis, "fetch").mockReturnValue(read.promise)
  vi.spyOn(console, "error").mockImplementation(() => {})
  element = document.createElement("div")
  element.id = "club_discussion_17"
  element.dataset.controller = "club-discussion"
  element.dataset.clubDiscussionBookClubIdValue = "17"
  element.dataset.clubDiscussionPageValue = "1"
  element.dataset.clubDiscussionTotalPostsValue = "1"
  element.dataset.clubDiscussionPaginationUrlValue = "/book_clubs/17/club_messages"
  element.dataset.clubDiscussionCurrentUserIdValue = "7"
  element.dataset.clubDiscussionCanPostValue = "true"
  element.dataset.action = "turbo:before-cache@document->club-discussion#beforeCache"
  element.innerHTML = `
    <section data-club-discussion-target="content">
      <p role="status" data-club-discussion-target="connectionStatus"></p>
      <button data-club-discussion-target="retry" data-action="club-discussion#recoverDiscussion" hidden>Retry</button>
      <div data-club-discussion-target="messages"><article id="club_message_1" data-message-id="1" data-author-id="7" data-updated-at="2026-10-21T12:00:00.000001Z"><p class="club-discussion-message-body">Thought 1</p></article></div>
      <p data-club-discussion-target="emptyState" hidden>No posts</p>
      <p data-club-discussion-target="paginationSummary"></p>
      <div data-club-discussion-target="pagination"></div>
      <form data-action="submit->club-discussion#postMessage"><textarea data-club-discussion-target="body">My unsent draft</textarea><button data-club-discussion-target="submit" disabled>Post</button><p data-club-discussion-target="composerStatus"></p></form>
    </section>
    <p role="status" data-club-discussion-target="status" hidden></p>`
  document.body.append(element)
  application = Application.start()
  application.register("club-discussion", ClubDiscussionController)
  application.register("club-message", ClubMessageController)
  await vi.waitFor(() => expect(subscribeTo).toHaveBeenCalledOnce())
})

afterEach(async () => {
  element.remove()
  await Promise.resolve()
  read.resolve(snapshot([]))
  await read.promise
  application.stop()
  vi.useRealTimers()
})

test("confirmed subscription requests the selected authorized page and becomes Live only after parsing recovery", async () => {
  expect(state()).toBe("connecting")
  expect(http).not.toHaveBeenCalled()
  await connect()
  expect(state()).toBe("recovering")
  expect(http).toHaveBeenCalledOnce()
  expect(String(http.mock.calls[0][0])).toContain("/book_clubs/17/club_messages?page=1")
  expect(http.mock.calls[0][1]).toMatchObject({ credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json" } })
  await finish([post(2), post(1)])
  expect(ids()).toEqual([2, 1])
  expect(element.querySelector("textarea")!.value).toBe("My unsent draft")
})

test("snapshot 39 40 42 and overlapping events 42 41 43 appear once each newest first", async () => {
  await connect()
  for (const id of [42, 41, 43, 42]) callbacks.received({ type: "message.created", message: post(id) })
  expect(ids()).toEqual([1])
  await finish([post(39), post(40), post(42)], 5)
  expect(ids()).toEqual([43, 42, 41, 40, 39])
})

test("a sixty-post response is bounded to the newest ten and does not execute user text", async () => {
  await connect()
  const posts = Array.from({ length: 60 }, (_, index) => post(index + 1))
  posts[59].body = "<script>alert('post')</script>"
  posts[59].author.nickname = "<img src=x onerror=alert(1)>"
  await finish(posts, 60)
  expect(ids()).toEqual([60, 59, 58, 57, 56, 55, 54, 53, 52, 51])
  expect(element.querySelector("#club_message_60 p")!.textContent).toBe(posts[59].body)
  expect(element.querySelector("#club_message_60 script, #club_message_60 img")).toBeNull()
})

test("empty recovery removes old posts and shows the empty state", async () => {
  await connect()
  await finish([])
  expect(ids()).toEqual([])
  expect(element.querySelector<HTMLElement>("[data-club-discussion-target='emptyState']")!.hidden).toBe(false)
})

test("more than ten buffered posts retain only the newest ten and do not lower a newer snapshot count", async () => {
  await connect()
  for (let id = 2; id <= 22; id += 1) callbacks.received({ type: "message.created", message: post(id), total_posts: id })
  await finish([post(23)], 23)
  expect(ids()).toEqual([23, 22, 21, 20, 19, 18, 17, 16, 15, 14])
  expect(element.querySelector("[data-club-discussion-target='paginationSummary']")!.textContent).toBe("23 posts · Page 1 of 3")
})

test("server failure retains the draft and allows a manual retry", async () => {
  await connect()
  read.resolve(new Response("Unavailable", { status: 503 }))
  await vi.waitFor(() => expect(state()).toBe("failed"))
  expect(ids()).toEqual([1])
  expect(element.querySelector("textarea")!.value).toBe("My unsent draft")
  expect(element.querySelector<HTMLButtonElement>("[data-club-discussion-target='retry']")!.hidden).toBe(false)
})

test("buffered edits and deletions override older snapshot versions without resurrecting deleted posts", async () => {
  await connect()
  callbacks.received({ type: "message.updated", message: post(2, { body: "Updated", updated_at: "2026-10-21T12:01:00Z" }) })
  callbacks.received({ type: "message.deleted", message: post(3, { body: "", deleted: true, updated_at: "2026-10-21T12:02:00Z" }) })
  callbacks.received({ type: "message.created", message: post(3) })
  await finish([post(1), post(2), post(3)])
  expect(ids()).toEqual([2, 1])
  expect(element.querySelector("#club_message_2 p")!.textContent).toBe("Updated")
})

test("recoverable failure preserves drafts and old posts merges buffered posts and exposes working Retry", async () => {
  await connect()
  callbacks.received({ type: "message.created", message: post(2) })
  read.reject(new Error("Network unavailable"))
  await vi.waitFor(() => expect(state()).toBe("failed"))
  expect(ids()).toEqual([2, 1])
  expect(element.querySelector("textarea")!.value).toBe("My unsent draft")
  const retry = element.querySelector<HTMLButtonElement>("[data-club-discussion-target='retry']")!
  expect(retry.hidden).toBe(false)
  read = Promise.withResolvers<Response>()
  http.mockReturnValue(read.promise)
  retry.click()
  retry.click()
  expect(http).toHaveBeenCalledTimes(2)
  expect(state()).toBe("recovering")
  await finish([post(3), post(2), post(1)])
  expect(ids()).toEqual([3, 2, 1])
  expect(retry.hidden).toBe(true)
})

test("historical recovery refreshes the selected page and keeps new posts on the first page", async () => {
  element.dataset.clubDiscussionPageValue = "3"
  await Promise.resolve()
  await connect()
  expect(String(http.mock.calls[0][0])).toContain("page=3")
  callbacks.received({ type: "message.created", message: post(60), total_posts: 60 })
  callbacks.received({ type: "message.updated", message: post(5, { body: "History edit", updated_at: "2026-10-21T12:01:00Z" }) })
  await finish([post(5), post(4)], 60)
  expect(ids()).toEqual([5, 4])
  expect(element.querySelector("#club_message_5 p")!.textContent).toBe("History edit")
  expect(element.querySelector("[data-club-discussion-target='status']")!.textContent).toContain("first page")
})

test("disconnect aborts recovery merges received events and reconnect starts a fresh read on the same subscription", async () => {
  await connect()
  const oldRead = read
  const signal = http.mock.calls[0][1]!.signal!
  callbacks.received({ type: "message.created", message: post(2) })
  callbacks.disconnected({ willAttemptReconnect: true })
  expect(signal.aborted).toBe(true)
  expect(state()).toBe("offline")
  expect(ids()).toEqual([2, 1])
  read = Promise.withResolvers<Response>()
  http.mockReturnValue(read.promise)
  callbacks.connected()
  callbacks.connected()
  expect(http).toHaveBeenCalledTimes(2)
  expect(subscribeTo).toHaveBeenCalledOnce()
  oldRead.resolve(snapshot([post(99)]))
  await finish([post(3), post(2), post(1)])
  expect(ids()).toEqual([3, 2, 1])
})

test("navigation aborts recovery and a late response cannot paint the detached discussion", async () => {
  await connect()
  const signal = http.mock.calls[0][1]!.signal!
  element.remove()
  await vi.waitFor(() => expect(signal.aborted).toBe(true))
  read.resolve(snapshot([post(99)]))
  await read.promise
  await Promise.resolve()
  expect(ids()).toEqual([1])
  expect(unsubscribe).toHaveBeenCalledOnce()
})

test("a stale JSON parse cannot paint after reconnect even when the HTTP response arrived earlier", async () => {
  const parsed = Promise.withResolvers<unknown>()
  const response = snapshot([])
  vi.spyOn(response, "json").mockReturnValue(parsed.promise)
  await connect()
  read.resolve(response)
  await vi.waitFor(() => expect(response.json).toHaveBeenCalledOnce())
  callbacks.disconnected({ willAttemptReconnect: true })
  read = Promise.withResolvers<Response>()
  http.mockReturnValue(read.promise)
  callbacks.connected()
  await finish([post(2), post(1)])
  parsed.resolve({ messages: [post(99)], total_posts: 1, pagination_html: "" })
  await parsed.promise
  await Promise.resolve()
  expect(ids()).toEqual([2, 1])
})

test.each([401, 403])("HTTP %s clears private content and unsubscribes instead of showing Retry", async status => {
  await connect()
  read.resolve(new Response("Denied", { status }))
  await vi.waitFor(() => expect(element.querySelector("[data-club-discussion-target='content']")!.textContent).toBe(""))
  expect(unsubscribe).toHaveBeenCalledOnce()
})

test("a redirected sign-in response clears private content", async () => {
  await connect()
  const response = new Response("Sign in", { headers: { "Content-Type": "text/html" } })
  Object.defineProperties(response, { redirected: { value: true }, url: { value: "http://localhost/users/sign_in" } })
  read.resolve(response)
  await vi.waitFor(() => expect(element.querySelector("textarea")).toBeNull())
  expect(unsubscribe).toHaveBeenCalledOnce()
})

test("membership revocation aborts the request discards its buffer and ignores late success", async () => {
  await connect()
  const signal = http.mock.calls[0][1]!.signal!
  callbacks.received({ type: "message.created", message: post(2) })
  callbacks.received({ type: "access.revoked" })
  read.resolve(snapshot([post(99)]))
  await read.promise
  await Promise.resolve()
  expect(signal.aborted).toBe(true)
  expect(element.querySelector("[data-club-discussion-target='content']")!.textContent).toBe("")
  expect(unsubscribe).toHaveBeenCalledOnce()
})

test("successful Cable posting during recovery is merged once without an HTTP write", async () => {
  await connect()
  element.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  await vi.waitFor(() => expect(perform).toHaveBeenCalledOnce())
  const requestId = perform.mock.calls[0][1].request_id
  callbacks.received({ type: "post.saved", request_id: requestId, message: post(2) })
  callbacks.received({ type: "message.created", message: post(2) })
  await finish([post(2), post(1)])
  expect(ids()).toEqual([2, 1])
  expect(element.querySelector("textarea")!.value).toBe("")
  expect(http).toHaveBeenCalledOnce()
  expect(http.mock.calls[0][1]?.method).toBeUndefined()
})

test("retained message nodes preserve open reply controls and their drafts during recovery", async () => {
  const article = element.querySelector("article")!
  const replies = document.createElement("section")
  replies.innerHTML = '<textarea>Unsent reply</textarea><button aria-expanded="true">Comments</button>'
  article.append(replies)
  await connect()
  await finish([post(2), post(1)])
  expect(element.querySelector("#club_message_1")).toBe(article)
  expect(replies.querySelector("textarea")!.value).toBe("Unsent reply")
  expect(replies.querySelector("button")!.getAttribute("aria-expanded")).toBe("true")
})

test("a posting acknowledgement received after its timeout is recovered without clearing the retained draft", async () => {
  vi.useFakeTimers()
  await connect()
  element.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  await vi.advanceTimersByTimeAsync(0)
  const requestId = perform.mock.calls.find(([action]) => action === "post_message")![1].request_id
  await vi.advanceTimersByTimeAsync(5_000)
  callbacks.received({ type: "post.saved", request_id: requestId, message: post(2) })
  read.resolve(snapshot([post(1)]))
  await vi.advanceTimersByTimeAsync(0)
  expect(state()).toBe("live")
  expect(ids()).toEqual([2, 1])
  expect(element.querySelector("textarea")!.value).toBe("My unsent draft")
  expect(perform.mock.calls.filter(([action]) => action === "post_message")).toHaveLength(1)
})

test("Turbo cache preparation clears private content aborts recovery and ignores late success", async () => {
  await connect()
  const signal = http.mock.calls[0][1]!.signal!
  document.dispatchEvent(new Event("turbo:before-cache"))
  read.resolve(snapshot([post(99)]))
  await read.promise
  await Promise.resolve()
  expect(signal.aborted).toBe(true)
  expect(element.querySelector("textarea")).toBeNull()
})

test("a malformed snapshot offers Retry without erasing existing posts or the draft", async () => {
  await connect()
  read.resolve(new Response(JSON.stringify({ messages: [], total_posts: "invalid" })))
  await vi.waitFor(() => expect(state()).toBe("failed"))
  expect(ids()).toEqual([1])
  expect(element.querySelector("textarea")!.value).toBe("My unsent draft")
})

test("a timed-out recovery offers Retry and does not automatically resend a post", async () => {
  vi.useFakeTimers()
  http.mockImplementation((_url, options) => new Promise((_resolve, reject) => {
    options!.signal!.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")))
  }))
  await connect()
  await vi.advanceTimersByTimeAsync(10_000)
  expect(state()).toBe("failed")
  expect(perform.mock.calls.some(([action]) => action === "post_message")).toBe(false)
  expect(element.querySelector("textarea")!.value).toBe("My unsent draft")
})
