import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi } from "vitest"
import ClubDiscussionController from "../../app/javascript/controllers/club_discussion_controller"
import type { DiscussionEvent, DiscussionMember } from "../../app/javascript/club_discussion/types"

interface Subscription {
  unsubscribe(): void
  perform(action: string, data: { request_id?: string; body?: string }): boolean
}

interface Callbacks {
  connected(): void
  received(event: DiscussionEvent): void
  rejected(): void
  disconnected(details: { willAttemptReconnect: boolean }): void
}

const { subscribeTo } = vi.hoisted(() => ({ subscribeTo: vi.fn() }))
vi.mock("@hotwired/turbo-rails", () => ({ cable: { subscribeTo } }))

let application: Application
let element: HTMLDivElement
let callbacks: Callbacks
let pending: ReturnType<typeof Promise.withResolvers<Subscription>>
let mainInput: HTMLTextAreaElement
let replyInput: HTMLTextAreaElement
let roster: HTMLUListElement
let presenceStatus: HTMLElement
let typingStatus: HTMLElement
let perform: ReturnType<typeof vi.fn<Subscription["perform"]>>
let unsubscribe: ReturnType<typeof vi.fn<Subscription["unsubscribe"]>>

beforeEach(async () => {
  pending = Promise.withResolvers<Subscription>()
  perform = vi.fn<Subscription["perform"]>().mockReturnValue(true)
  unsubscribe = vi.fn<Subscription["unsubscribe"]>()
  subscribeTo.mockImplementation((_channel: unknown, handlers: Callbacks) => {
    callbacks = handlers
    return pending.promise
  })
  element = document.createElement("div")
  element.dataset.controller = "club-discussion"
  element.dataset.clubDiscussionBookClubIdValue = "17"
  element.dataset.clubDiscussionCurrentUserIdValue = "7"
  element.dataset.clubDiscussionCanPostValue = "true"
  element.dataset.action = "turbo:before-cache@document->club-discussion#beforeCache"
  element.innerHTML = `
    <section data-club-discussion-target="content">
      <section aria-labelledby="presence-heading">
        <h2 id="presence-heading">Online members</h2>
        <p role="status" data-club-discussion-target="presenceStatus">Presence unavailable</p>
        <ul data-club-discussion-target="onlineMembers" hidden></ul>
      </section>
      <p class="club-discussion-sr-only" role="status" data-club-discussion-target="typingStatus"></p>
      <template data-club-discussion-target="typingIndicator"><img src="/assets/discussion-typing-dot.svg" alt="" width="6" height="6"><span>Writing a post…</span></template>
      <div data-club-discussion-target="messages">Discussion history</div>
      <p data-club-discussion-target="emptyState" hidden></p>
      <p data-club-discussion-target="paginationSummary"></p>
      <div data-club-discussion-target="pagination"></div>
      <form data-action="submit->club-discussion#postMessage">
        <textarea data-club-discussion-target="body" data-action="input->club-discussion#typing"></textarea>
        <button data-club-discussion-target="submit" disabled>Post</button>
        <p data-club-discussion-target="composerStatus"></p>
      </form>
      <textarea id="reply" data-action="input->club-discussion#typing"></textarea>
      <textarea id="edit"></textarea>
    </section>
    <p data-club-discussion-target="status" hidden></p>
  `
  mainInput = element.querySelector<HTMLTextAreaElement>("[data-club-discussion-target='body']")!
  replyInput = element.querySelector<HTMLTextAreaElement>("#reply")!
  roster = element.querySelector<HTMLUListElement>("[data-club-discussion-target='onlineMembers']")!
  presenceStatus = element.querySelector<HTMLElement>("[data-club-discussion-target='presenceStatus']")!
  typingStatus = element.querySelector<HTMLElement>("[data-club-discussion-target='typingStatus']")!
  document.body.append(element)
  application = Application.start()
  application.register("club-discussion", ClubDiscussionController)
  await vi.waitFor(() => expect(subscribeTo).toHaveBeenCalledOnce())
})

afterEach(async () => {
  element.remove()
  await Promise.resolve()
  pending.resolve({ perform, unsubscribe })
  await pending.promise
  await Promise.resolve()
  application.stop()
  vi.useRealTimers()
})

async function confirmConnection() {
  pending.resolve({ perform, unsubscribe })
  await pending.promise
  callbacks.connected()
}

function snapshot(members: DiscussionMember[] = [{ id: 7, nickname: "Joon" }, { id: 9, nickname: "Mina" }], generatedAt = new Date().toISOString()) {
  callbacks.received({ type: "presence.snapshot", members, generated_at: generatedAt })
}

function typing(token = "mina-tab-a", member = { id: 9, nickname: "Mina" }, generatedAt = new Date().toISOString()) {
  callbacks.received({ type: "typing.started", member, connection_token: token, generated_at: generatedAt })
}

function input(textarea: HTMLTextAreaElement, value = "A private draft") {
  textarea.value = value
  textarea.dispatchEvent(new Event("input", { bubbles: true }))
}

test("presence starts unavailable and accepts an initial snapshot before connection confirmation", () => {
  expect(presenceStatus.textContent).toBe("Presence unavailable")
  expect(roster.hidden).toBe(true)

  snapshot([{ id: 9, nickname: "<img src=x onerror=alert(1)>" }, { id: 9, nickname: "<img src=x onerror=alert(1)>" }])

  expect(roster.children).toHaveLength(1)
  expect(roster.querySelector("strong")!.textContent).toBe("<img src=x onerror=alert(1)>")
  expect(roster.querySelector("img")).toBeNull()
  expect(roster.hidden).toBe(false)
  expect(presenceStatus.textContent).toBe("1 member online.")
})

test("an empty successful snapshot shows zero members rather than unavailable", () => {
  snapshot([])

  expect(presenceStatus.textContent).toBe("0 members online.")
  expect(roster.hidden).toBe(true)
})

test("presence members use the shared profile image when an avatar URL is supplied", () => {
  const avatarUrl = "/rails/active_storage/blobs/redirect/signed-id/avatar.jpg"
  snapshot([{ id: 7, nickname: "Admin", avatar_url: avatarUrl }])

  const avatar = roster.querySelector(".profile-avatar--club_member")!
  expect(avatar.querySelector("img")!.getAttribute("src")).toBe(avatarUrl)
  expect(avatar.querySelector(".profile-avatar-initials")).toBeNull()
  expect(avatar.hasAttribute("data-presence-color")).toBe(false)
})

test("the Figma roster puts the current user first and shows initials and per-member typing status", async () => {
  vi.useFakeTimers()
  snapshot([
    { id: 9, nickname: "Lena Ortiz" },
    { id: 10, nickname: "Theo Brooks" },
    { id: 7, nickname: "Maya Chen" },
    { id: 11, nickname: "Amara Singh" }
  ])
  const rows = Array.from(roster.children)
  expect(rows.map(row => row.querySelector("strong")!.textContent)).toEqual(["Maya Chen", "Lena Ortiz", "Theo Brooks", "Amara Singh"])
  expect(rows.map(row => row.querySelector(".profile-avatar-initials")!.textContent)).toEqual(["MA", "LE", "TH", "AM"])
  expect(rows.map(row => row.querySelector(".club-presence-member-status")!.textContent)).toEqual(["You", "Online", "Online", "Online"])
  expect(presenceStatus.classList.contains("club-discussion-sr-only")).toBe(true)

  typing("lena-tab", { id: 9, nickname: "Lena Ortiz" })
  typing("theo-tab", { id: 10, nickname: "Theo Brooks" })
  typing("maya-other-tab", { id: 7, nickname: "Maya Chen" })

  expect(rows.map(row => row.querySelector(".club-presence-member-status")!.textContent)).toEqual(["Writing a post…", "Writing a post…", "Writing a post…", "Online"])
  const dot = rows[1].querySelector<HTMLImageElement>(".club-presence-member-status img")!
  expect(dot.getAttribute("src")).toContain("discussion-typing-dot.svg")
  expect(dot.getAttribute("width")).toBe("6")
  expect(dot.getAttribute("height")).toBe("6")
  expect(typingStatus.classList.contains("club-discussion-sr-only")).toBe(true)

  await vi.advanceTimersByTimeAsync(3_000)
  expect(rows.map(row => row.querySelector(".club-presence-member-status")!.textContent)).toEqual(["You", "Online", "Online", "Online"])
  expect(roster.querySelector(".club-presence-member-status img")).toBeNull()
})

test("older snapshots cannot replace a newer roster", () => {
  snapshot([{ id: 9, nickname: "Mina" }], "2026-10-23T12:00:01.000002Z")
  snapshot([], "2026-10-23T12:00:01.000001Z")

  expect(roster.querySelector("strong")!.textContent).toBe("Mina")
})

test("typing is tracked per connection but one user is displayed once", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  snapshot()
  typing("mina-tab-a")
  await vi.advanceTimersByTimeAsync(1_000)
  typing("mina-tab-b")
  expect(typingStatus.textContent).toBe("Mina is typing…")

  await vi.advanceTimersByTimeAsync(2_000)
  expect(typingStatus.textContent).toBe("Mina is typing…")
  await vi.advanceTimersByTimeAsync(1_000)
  expect(typingStatus.textContent).toBe("")
})

test("typing renewal extends only that connection and older events do not replace it", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  snapshot()
  const firstTimestamp = new Date().toISOString()
  typing()
  await vi.advanceTimersByTimeAsync(2_000)
  typing()
  typing("mina-tab-a", { id: 9, nickname: "Old name" }, firstTimestamp)

  await vi.advanceTimersByTimeAsync(2_999)
  expect(typingStatus.textContent).toBe("Mina is typing…")
  await vi.advanceTimersByTimeAsync(1)
  expect(typingStatus.textContent).toBe("")
})

test("the current user's tabs show one typing indicator until the last connection expires", async () => {
  vi.useFakeTimers()
  snapshot([{ id: 7, nickname: "Joon" }])
  const status = roster.querySelector(".club-presence-member-status")!
  expect(status.textContent).toBe("You")

  typing("own-tab-a", { id: 7, nickname: "Joon" })
  await vi.advanceTimersByTimeAsync(1_000)
  typing("own-tab-b", { id: 7, nickname: "Joon" })
  expect(typingStatus.textContent).toBe("Joon is typing…")
  expect(status.textContent).toBe("Writing a post…")
  expect(status.querySelectorAll("img")).toHaveLength(1)

  await vi.advanceTimersByTimeAsync(2_000)
  expect(status.textContent).toBe("Writing a post…")
  await vi.advanceTimersByTimeAsync(1_000)
  expect(status.textContent).toBe("You")
  expect(status.querySelector("img")).toBeNull()
  expect(typingStatus.textContent).toBe("")
})

test("multiple typists are displayed safely and leaving the roster clears their typing", () => {
  const timestamp = Date.now()
  snapshot([{ id: 9, nickname: "Mina" }, { id: 10, nickname: "<script>alert(1)</script>" }], new Date(timestamp).toISOString())
  typing()
  typing("another-tab", { id: 10, nickname: "<script>alert(1)</script>" })
  expect(typingStatus.textContent).toBe("Mina, <script>alert(1)</script> are typing…")
  expect(typingStatus.querySelector("script")).toBeNull()

  snapshot([{ id: 9, nickname: "Mina" }], new Date(timestamp + 1).toISOString())

  expect(typingStatus.textContent).toBe("Mina is typing…")
})

test("already expired typing events do not restore an indicator", () => {
  snapshot()

  typing("old-tab", { id: 9, nickname: "Mina" }, new Date(Date.now() - 3_000).toISOString())

  expect(typingStatus.textContent).toBe("")
})

test("post and reply inputs share one throttle and send no draft or identity", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  input(mainInput)
  input(replyInput)
  await vi.advanceTimersByTimeAsync(999)
  expect(perform).toHaveBeenCalledExactlyOnceWith("typing", {})

  await vi.advanceTimersByTimeAsync(1)
  input(replyInput)
  await vi.advanceTimersByTimeAsync(0)
  expect(perform).toHaveBeenCalledTimes(2)
  expect(subscribeTo).toHaveBeenCalledOnce()
})

test("a typing burst has no delayed trailing send", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  input(mainInput)
  input(mainInput)

  await vi.advanceTimersByTimeAsync(2_000)

  expect(perform).toHaveBeenCalledExactlyOnceWith("typing", {})
})

test("blank disabled readonly and edit inputs do not send typing", async () => {
  await confirmConnection()
  input(mainInput, "   ")
  mainInput.readOnly = true
  input(mainInput)
  mainInput.readOnly = false
  mainInput.disabled = true
  input(mainInput)
  input(element.querySelector<HTMLTextAreaElement>("#edit")!)
  await Promise.resolve()

  expect(perform).not.toHaveBeenCalled()
})

test("a read-only admin sees presence but cannot send typing", async () => {
  element.dataset.clubDiscussionCanPostValue = "false"
  await Promise.resolve()
  await confirmConnection()
  snapshot()
  input(mainInput)
  await Promise.resolve()

  expect(roster.children).toHaveLength(2)
  expect(perform).not.toHaveBeenCalled()
})

test("disconnection cancels pending typing and clears presence and expiry timers", async () => {
  vi.useFakeTimers()
  callbacks.connected()
  snapshot()
  typing()
  input(mainInput)
  callbacks.disconnected({ willAttemptReconnect: true })
  pending.resolve({ perform, unsubscribe })
  await vi.advanceTimersByTimeAsync(0)

  expect(perform).not.toHaveBeenCalled()
  expect(roster.children).toHaveLength(0)
  expect(typingStatus.textContent).toBe("")
  expect(presenceStatus.textContent).toBe("Presence unavailable")
  expect(vi.getTimerCount()).toBe(0)
  snapshot()
  expect(roster.children).toHaveLength(0)
})

test.each(["rejection", "access revocation", "permanent disconnection"])("%s clears active presence timers and releases a subscription that finishes setup later", async reason => {
  vi.useFakeTimers()
  callbacks.connected()
  snapshot()
  typing()
  input(mainInput)
  expect(vi.getTimerCount()).toBeGreaterThan(0)

  if (reason === "rejection") {
    callbacks.rejected()
  } else if (reason === "access revocation") {
    callbacks.received({ type: "access.revoked" })
  } else {
    callbacks.disconnected({ willAttemptReconnect: false })
  }
  expect(vi.getTimerCount()).toBe(0)
  expect(element.querySelector("[data-club-discussion-target='onlineMembers']")).toBeNull()
  expect(element.querySelector("[data-club-discussion-target='typingStatus']")).toBeNull()
  expect(element.querySelector("[data-club-discussion-target='content']")!.textContent).toBe("")

  pending.resolve({ perform, unsubscribe })
  await vi.advanceTimersByTimeAsync(60_000)
  snapshot()
  typing()

  expect(unsubscribe).toHaveBeenCalledOnce()
  expect(perform).not.toHaveBeenCalled()
  expect(element.querySelector("[data-club-discussion-target='content']")!.textContent).toBe("")
  expect(vi.getTimerCount()).toBe(0)
})

test("Redis unavailability clears transient UI and preserves discussion and the draft", async () => {
  await confirmConnection()
  snapshot()
  typing()
  mainInput.value = "Keep this draft"

  callbacks.received({ type: "presence.unavailable" })

  expect(roster.children).toHaveLength(0)
  expect(typingStatus.textContent).toBe("")
  expect(presenceStatus.textContent).toBe("Presence unavailable")
  expect(mainInput.value).toBe("Keep this draft")
  expect(element.querySelector("[data-club-discussion-target='messages']")!.textContent).toBe("Discussion history")
  expect(element.querySelector<HTMLButtonElement>("[data-club-discussion-target='submit']")!.disabled).toBe(false)
})

test("a fresh snapshot after Redis failure restores presence without restoring old typing or replacing the subscription", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  snapshot()
  typing()
  mainInput.value = "Keep this draft"
  callbacks.received({ type: "presence.unavailable" })
  expect(vi.getTimerCount()).toBe(1)

  await vi.advanceTimersByTimeAsync(10_000)
  expect(perform).toHaveBeenCalledExactlyOnceWith("heartbeat", {})
  snapshot([{ id: 7, nickname: "Joon" }, { id: 10, nickname: "Lena" }])

  expect(Array.from(roster.querySelectorAll("strong"), name => name.textContent)).toEqual(["Joon", "Lena"])
  expect(presenceStatus.classList.contains("club-discussion-sr-only")).toBe(true)
  expect(typingStatus.textContent).toBe("")
  expect(mainInput.value).toBe("Keep this draft")
  expect(subscribeTo).toHaveBeenCalledOnce()
  expect(unsubscribe).not.toHaveBeenCalled()
})

test("reconnection discards pending typing from the old connection and allows new input", async () => {
  vi.useFakeTimers()
  callbacks.connected()
  input(mainInput)
  callbacks.disconnected({ willAttemptReconnect: true })
  callbacks.connected()
  pending.resolve({ perform, unsubscribe })
  await vi.advanceTimersByTimeAsync(0)
  expect(perform).not.toHaveBeenCalled()

  snapshot()
  input(replyInput)
  await vi.advanceTimersByTimeAsync(0)
  expect(perform).toHaveBeenCalledExactlyOnceWith("typing", {})
  expect(roster.children).toHaveLength(2)
})

test("an input removed while subscription setup is pending cannot send late typing", async () => {
  vi.useFakeTimers()
  callbacks.connected()
  input(replyInput)
  replyInput.remove()
  pending.resolve({ perform, unsubscribe })

  await vi.advanceTimersByTimeAsync(0)

  expect(perform).not.toHaveBeenCalled()
})

test("missing snapshots show unavailable after 55 seconds and a fresh snapshot restores presence", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  snapshot()
  await vi.advanceTimersByTimeAsync(54_999)
  expect(roster.children).toHaveLength(2)

  await vi.advanceTimersByTimeAsync(1)
  expect(presenceStatus.textContent).toBe("Presence unavailable")
  expect(roster.children).toHaveLength(0)
  snapshot()
  expect(roster.children).toHaveLength(2)
})

test("duplicate snapshots do not extend the freshness timeout", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  const timestamp = new Date().toISOString()
  snapshot(undefined, timestamp)
  await vi.advanceTimersByTimeAsync(30_000)
  snapshot(undefined, timestamp)
  await vi.advanceTimersByTimeAsync(25_000)

  expect(presenceStatus.textContent).toBe("Presence unavailable")
})

test("a newer snapshot restarts the 55 second freshness deadline", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  snapshot()
  await vi.advanceTimersByTimeAsync(30_000)
  snapshot()

  await vi.advanceTimersByTimeAsync(25_000)
  expect(roster.children).toHaveLength(2)
  await vi.advanceTimersByTimeAsync(29_999)
  expect(roster.children).toHaveLength(2)
  await vi.advanceTimersByTimeAsync(1)
  expect(roster.children).toHaveLength(0)
  expect(presenceStatus.textContent).toBe("Presence unavailable")
})

test("Turbo navigation cancels transient timers and ignores late presence events", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  snapshot()
  typing()

  document.dispatchEvent(new Event("turbo:before-cache"))
  snapshot()
  typing()
  await vi.advanceTimersByTimeAsync(60_000)

  expect(element.querySelector("[data-club-discussion-target='content']")!.textContent).toBe("")
  expect(vi.getTimerCount()).toBe(0)
  expect(unsubscribe).toHaveBeenCalledOnce()
})

test("typing send failures are reported and a later input can succeed", async () => {
  vi.useFakeTimers()
  await confirmConnection()
  const error = new Error("Typing send failed")
  const errorLog = vi.spyOn(console, "error").mockImplementation(() => {})
  perform.mockImplementationOnce(() => { throw error })
  input(mainInput)
  await vi.advanceTimersByTimeAsync(1_000)
  expect(errorLog).toHaveBeenCalledWith("Failed to send club typing event", error)

  input(replyInput)
  await vi.advanceTimersByTimeAsync(0)
  expect(perform).toHaveBeenCalledTimes(2)
})
