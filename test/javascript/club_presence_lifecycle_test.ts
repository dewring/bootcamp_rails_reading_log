import { afterEach, beforeEach, expect, test, vi } from "vitest"
import ClubPresence from "../../app/javascript/club_discussion/presence"
import type { DiscussionSubscription } from "../../app/javascript/club_discussion/types"

let root: HTMLElement
let presence: ClubPresence
let pending: ReturnType<typeof Promise.withResolvers<DiscussionSubscription | undefined>>
let perform: ReturnType<typeof vi.fn<DiscussionSubscription["perform"]>>

beforeEach(() => {
  vi.useFakeTimers()
  root = document.createElement("section")
  root.innerHTML = '<p role="status"></p><ul></ul><textarea>Private draft</textarea>'
  document.body.append(root)
  pending = Promise.withResolvers<DiscussionSubscription | undefined>()
  perform = vi.fn<DiscussionSubscription["perform"]>().mockReturnValue(true)
  presence = new ClubPresence({
    root,
    currentUserId: () => 7,
    canPost: () => true,
    targets: () => ({
      onlineMembers: root.querySelector("ul") ?? undefined,
      presenceStatus: root.querySelector("p") ?? undefined
    })
  })
})

afterEach(() => {
  presence.disconnect()
  root.remove()
  vi.useRealTimers()
})

test("a pending heartbeat cannot send after disconnect even if subscription setup finishes later", async () => {
  presence.subscriptionConfirmed(pending.promise)
  await vi.advanceTimersByTimeAsync(10_000)
  presence.disconnect()
  pending.resolve({ perform, unsubscribe: vi.fn() })
  await vi.advanceTimersByTimeAsync(0)

  expect(perform).not.toHaveBeenCalled()
  expect(vi.getTimerCount()).toBe(0)
  expect(root.querySelector("textarea")!.value).toBe("Private draft")
})

test("reconnection keeps only the new heartbeat and discards a pending typing send from the previous connection", async () => {
  presence.subscriptionConfirmed(pending.promise)
  const input = root.querySelector("textarea")!
  const event = new Event("input")
  input.addEventListener("input", received => presence.typing(received), { once: true })
  input.dispatchEvent(event)
  presence.disconnect()
  presence.subscriptionConfirmed(pending.promise)
  pending.resolve({ perform, unsubscribe: vi.fn() })
  await vi.advanceTimersByTimeAsync(0)
  expect(perform).not.toHaveBeenCalled()

  await vi.advanceTimersByTimeAsync(10_000)
  expect(perform).toHaveBeenCalledExactlyOnceWith("heartbeat", {})
  expect(vi.getTimerCount()).toBe(1)
})

test("disconnect releases expiry timers even after the surrounding private content has been removed", () => {
  presence.subscriptionConfirmed(pending.promise)
  presence.receiveEvent({ type: "presence.snapshot", members: [{ id: 9, nickname: "Mina" }], generated_at: new Date().toISOString() })
  presence.receiveEvent({ type: "typing.started", member: { id: 9, nickname: "Mina" }, connection_token: "mina-tab", generated_at: new Date().toISOString() })
  expect(vi.getTimerCount()).toBeGreaterThan(1)
  root.replaceChildren()

  presence.disconnect()

  expect(vi.getTimerCount()).toBe(0)
  expect(root.textContent).toBe("")
})

test("presence transport errors are reported and do not prevent the next heartbeat", async () => {
  const error = new Error("Heartbeat unavailable")
  const log = vi.spyOn(console, "error").mockImplementation(() => {})
  perform.mockImplementationOnce(() => { throw error })
  pending.resolve({ perform, unsubscribe: vi.fn() })
  presence.subscriptionConfirmed(pending.promise)

  await vi.advanceTimersByTimeAsync(10_000)
  expect(log).toHaveBeenCalledWith("Failed to send club presence heartbeat", error)
  await vi.advanceTimersByTimeAsync(10_000)
  expect(perform).toHaveBeenCalledTimes(2)
})
