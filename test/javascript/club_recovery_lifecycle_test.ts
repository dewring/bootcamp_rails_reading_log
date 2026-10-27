import { afterEach, beforeEach, expect, test, vi } from "vitest"
import DiscussionRecovery from "../../app/javascript/club_discussion/recovery"
import type { DiscussionEvent } from "../../app/javascript/club_discussion/types"

let root: HTMLElement
let recovery: DiscussionRecovery
let response: ReturnType<typeof Promise.withResolvers<Response>>
let replayed: DiscussionEvent[]

beforeEach(() => {
  vi.useFakeTimers()
  root = document.createElement("section")
  document.body.append(root)
  response = Promise.withResolvers<Response>()
  vi.spyOn(globalThis, "fetch").mockReturnValue(response.promise)
  const subscription = Promise.resolve(undefined)
  replayed = []
  recovery = new DiscussionRecovery({
    root,
    context: () => ({ connected: true, subscription, url: "/book_clubs/17/club_messages", page: 1 }),
    targets: () => ({}),
    beforeRead: () => {},
    applyHistory: () => {},
    replayEvents: events => replayed.push(...events),
    endAccess: () => recovery.disconnect()
  })
})

afterEach(() => {
  recovery.disconnect()
  root.remove()
  vi.useRealTimers()
})

test("disconnect releases the recovery timeout even when the transport ignores cancellation", async () => {
  const work = recovery.recoverPage()
  expect(vi.getTimerCount()).toBe(1)

  recovery.disconnect()

  expect(vi.getTimerCount()).toBe(0)
  expect(recovery.isRecovering).toBe(false)
  response.resolve(new Response(JSON.stringify({ messages: [], total_posts: 0, pagination_html: "" })))
  await work
  expect(root.dataset.connectionState).toBe("offline")
})

test("connection loss replays buffered events once while navigation discards them", async () => {
  const event: DiscussionEvent = { type: "message.created" }
  const first = recovery.recoverPage()
  expect(recovery.bufferEvent(event)).toBe(true)
  recovery.connectionLost()
  recovery.connectionLost()
  expect(replayed).toEqual([event])

  const second = recovery.recoverPage()
  expect(recovery.bufferEvent(event)).toBe(true)
  recovery.disconnect()
  expect(replayed).toEqual([event])
  expect(recovery.bufferEvent(event)).toBe(false)
  response.resolve(new Response("Old response"))
  await Promise.all([first, second])
  expect(root.dataset.connectionState).toBe("offline")
})
