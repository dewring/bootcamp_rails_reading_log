import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi } from "vitest"
import ClubRepliesController from "../../app/javascript/controllers/club_replies_controller"

let application: Application
let element: HTMLElement
let toggle: HTMLButtonElement
let panel: HTMLElement
let more: HTMLButtonElement
const fetchHistory = vi.fn<typeof fetch>()

beforeEach(async () => {
  vi.stubGlobal("fetch", fetchHistory)
  fetchHistory.mockReset()
  element = document.createElement("div")
  element.dataset.controller = "club-replies"
  element.dataset.clubRepliesPostIdValue = "7"
  element.dataset.clubRepliesUrlValue = "/book_clubs/17/club_messages/7/replies"
  element.dataset.action = "turbo:before-cache@document->club-replies#beforeCache"
  element.innerHTML = `<button data-club-replies-target="toggle" data-action="club-replies#toggle" aria-expanded="false"><span data-club-replies-target="countLabel">0 comments</span></button><div data-club-replies-target="panel" hidden><div data-club-replies-target="list"></div><p role="status" data-club-replies-target="status"></p><button data-club-replies-target="more" data-action="club-replies#loadMore" hidden>Load more replies</button></div>`
  document.body.append(element)
  toggle = element.querySelector("button")!
  panel = element.querySelector("[data-club-replies-target='panel']")!
  more = element.querySelector("[data-club-replies-target='more']")!
  application = Application.start()
  application.register("club-replies", ClubRepliesController)
  await vi.waitFor(() => expect(toggle.getAttribute("aria-controls")).toBe("club_replies_7"))
})

afterEach(async () => {
  element.remove()
  await Promise.resolve()
  application.stop()
  vi.unstubAllGlobals()
})

function history(ids: number[], nextPage: number | null = null) {
  return new Response(JSON.stringify({
    replies: ids.map(id => ({ id, parent_id: 7, body: `Answer ${id}`, author: { id: 1, nickname: "Reader" }, created_at: "2026-10-20T12:30:00Z", updated_at: "2026-10-20T12:30:00Z" })),
    pagination: { next_page: nextPage }
  }), { status: 200 })
}

test("opening replies loads the first page and collapsing preserves the loaded replies", async () => {
  fetchHistory.mockResolvedValue(history([8, 9]))
  expect(fetchHistory).not.toHaveBeenCalled()
  toggle.click()
  await vi.waitFor(() => expect(panel.querySelectorAll("article")).toHaveLength(2))
  expect(panel.hidden).toBe(false)
  expect(toggle.getAttribute("aria-expanded")).toBe("true")
  toggle.click()
  expect(panel.hidden).toBe(true)
  toggle.click()
  expect(fetchHistory).toHaveBeenCalledOnce()
})

test("loading the next page appends replies in server order and ignores duplicate ids", async () => {
  fetchHistory.mockResolvedValueOnce(history([8, 9], 2)).mockResolvedValueOnce(history([9, 10]))
  toggle.click()
  await vi.waitFor(() => expect(more.hidden).toBe(false))
  more.click()
  await vi.waitFor(() => expect(panel.querySelectorAll("article")).toHaveLength(3))
  expect(Array.from(panel.querySelectorAll("article"), reply => reply.id)).toEqual(["club_message_8", "club_message_9", "club_message_10"])
  expect(String(fetchHistory.mock.calls[1][0])).toContain("page=2")
  expect(more.hidden).toBe(true)
})

test("reply bodies and author names are rendered as text", async () => {
  const response = history([8])
  const data = await response.json()
  data.replies[0].body = "<script>unsafe()</script>"
  data.replies[0].author.nickname = "<img src=x onerror=unsafe()>"
  fetchHistory.mockResolvedValue(new Response(JSON.stringify(data)))
  toggle.click()
  await vi.waitFor(() => expect(panel.querySelector("article")).not.toBeNull())
  expect(panel.querySelector("script, img")).toBeNull()
  expect(panel.textContent).toContain("<script>unsafe()</script>")
})

test.each([
  { timestamp: "2026-10-20T00:05:00Z", expected: "Oct 20, 2026, 00:05" },
  { timestamp: "2026-10-20T13:45:00Z", expected: "Oct 20, 2026, 13:45" }
])("replies display $timestamp as $expected without AM or PM", async ({ timestamp, expected }) => {
  const data = await history([8]).json()
  data.replies[0].created_at = timestamp
  fetchHistory.mockResolvedValue(new Response(JSON.stringify(data)))

  toggle.click()

  await vi.waitFor(() => expect(panel.querySelector("time")?.textContent).toBe(expected))
  expect(panel.querySelector("time")?.getAttribute("datetime")).toBe(timestamp)
})

test("a failed read offers a manual retry without automatically repeating the request", async () => {
  fetchHistory.mockRejectedValueOnce(new Error("Offline")).mockResolvedValueOnce(history([8]))
  vi.spyOn(console, "error").mockImplementation(() => {})
  toggle.click()
  await vi.waitFor(() => expect(panel.textContent).toContain("Replies could not load"))
  expect(fetchHistory).toHaveBeenCalledOnce()
  more.click()
  await vi.waitFor(() => expect(panel.querySelectorAll("article")).toHaveLength(1))
})

test("repeated clicks do not start another request while a reply read is pending", async () => {
  const pending = Promise.withResolvers<Response>()
  fetchHistory.mockReturnValue(pending.promise)
  toggle.click()
  toggle.click()
  toggle.click()
  expect(fetchHistory).toHaveBeenCalledOnce()
  pending.resolve(history([8]))
  await vi.waitFor(() => expect(panel.querySelectorAll("article")).toHaveLength(1))
})

test("navigation aborts pending reads and prevents late private replies from rendering", async () => {
  const pending = Promise.withResolvers<Response>()
  fetchHistory.mockReturnValue(pending.promise)
  toggle.click()
  const signal = fetchHistory.mock.calls[0][1]!.signal!
  element.remove()
  await vi.waitFor(() => expect(signal.aborted).toBe(true))
  pending.resolve(history([8]))
  await pending.promise
  await Promise.resolve()
  expect(panel.querySelector("article")).toBeNull()
})

test("Turbo caching clears loaded reply data and collapses the panel", async () => {
  fetchHistory.mockResolvedValue(history([8]))
  toggle.click()
  await vi.waitFor(() => expect(panel.querySelector("article")).not.toBeNull())
  document.dispatchEvent(new Event("turbo:before-cache"))
  expect(panel.querySelector("article")).toBeNull()
  expect(panel.hidden).toBe(true)
  expect(toggle.getAttribute("aria-expanded")).toBe("false")
})

test("a forbidden reply read reports lost access to the enclosing discussion controller", async () => {
  fetchHistory.mockResolvedValue(new Response("", { status: 403 }))
  const revoked = vi.fn()
  element.addEventListener("club-replies:access-revoked", revoked)
  toggle.click()
  await vi.waitFor(() => expect(revoked).toHaveBeenCalledOnce())
  expect(panel.querySelector("article")).toBeNull()
})

test("reconnecting can start a fresh read without accepting the old response", async () => {
  const oldRead = Promise.withResolvers<Response>()
  fetchHistory.mockReturnValueOnce(oldRead.promise).mockResolvedValueOnce(history([9]))
  toggle.click()
  element.remove()
  await Promise.resolve()
  document.body.append(element)
  await Promise.resolve()
  toggle.click()
  toggle.click()
  await vi.waitFor(() => expect(panel.querySelector("#club_message_9")).not.toBeNull())
  oldRead.resolve(history([8]))
  await oldRead.promise
  await Promise.resolve()
  expect(panel.querySelector("#club_message_8")).toBeNull()
})
