import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi, type Mock } from "vitest"
import ClubMessageController from "../../app/javascript/controllers/club_message_controller"
import ClubRepliesController from "../../app/javascript/controllers/club_replies_controller"
import ClubDiscussionController from "../../app/javascript/controllers/club_discussion_controller"
import type { DiscussionMessage } from "../../app/javascript/controllers/club_discussion_controller"

interface Subscription {
  unsubscribe(): void
  perform(action: string, data: { request_id: string; body?: string; parent_id?: number; message_id?: number }): boolean
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
    <section data-club-discussion-target="content"><div data-club-discussion-target="messages"><article id="club_message_1" data-message-id="1">Private discussion</article></div><p data-club-discussion-target="emptyState" hidden></p><p data-club-discussion-target="paginationSummary"></p><div data-club-discussion-target="pagination"></div></section>
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

function enableMessageEditing() {
  element.id = "club_discussion_17"
  element.dataset.clubDiscussionCurrentUserIdValue = "7"
  element.dataset.clubDiscussionCanPostValue = "true"
  application.register("club-message", ClubMessageController)
  const template = document.createElement("template")
  template.dataset.clubDiscussionTarget = "editor"
  template.innerHTML = `<div class="club-message-editor"><button data-club-message-target="editButton" data-action="club-message#edit">Edit</button><form data-club-message-target="form" data-action="submit->club-message#save" hidden><label data-club-message-target="label">Edit your message</label><textarea data-club-message-target="input"></textarea><button type="submit" data-club-message-target="save">Save</button><button type="button" data-club-message-target="cancel" data-action="club-message#cancel">Cancel</button></form></div>`
  content.append(template)
}

function editingControls(article: HTMLElement) {
  return {
    article,
    body: article.querySelector<HTMLElement>("[data-club-message-target='body']")!,
    edit: article.querySelector<HTMLButtonElement>("[data-club-message-target='editButton']")!,
    form: article.querySelector<HTMLFormElement>("[data-club-message-target='form']")!,
    input: article.querySelector<HTMLTextAreaElement>("[data-club-message-target='input']")!,
    save: article.querySelector<HTMLButtonElement>("[data-club-message-target='save']")!,
    cancel: article.querySelector<HTMLButtonElement>("[data-club-message-target='cancel']")!,
    notice: article.querySelector<HTMLElement>("[data-club-message-target='status']")!
  }
}

async function mountEditablePost() {
  enableMessageEditing()
  completeSetup(requests[0])
  await requests[0].promise
  requests[0].callbacks.connected()
  requests[0].callbacks.received(createdMessageEvent(2))
  const article = messages.querySelector<HTMLElement>("#club_message_2")!
  await vi.waitFor(() => expect(article.querySelector("label")!.htmlFor).toBe("club_message_edit_2"))
  return editingControls(article)
}

function editedMessage(id: number, body: string, version = "2026-10-21T12:00:00.000001Z") {
  return { ...createdMessageEvent(id).message, body, updated_at: version }
}

function enableMessageDeletion() {
  const template = document.createElement("template")
  template.dataset.clubDiscussionTarget = "deleteButton"
  template.innerHTML = `<button type="button" data-club-message-target="deleteButton" data-action="club-message#deleteMessage">Delete</button>`
  content.append(template)
}

function deletionEvent(id: number, parentId: number | null = null) {
  return {
    type: parentId === null ? "message.deleted" : "reply.deleted",
    message: { ...editedMessage(id, ""), parent_id: parentId, deleted: true, replies_count: parentId === null ? 1 : 0 }
  }
}

async function mountDeletablePost() {
  enableMessageDeletion()
  const editor = await mountEditablePost()
  const button = editor.article.querySelector<HTMLButtonElement>("[data-club-message-target='deleteButton']")!
  vi.spyOn(window, "confirm").mockReturnValue(true)
  return { ...editor, button }
}

test("confirmed deletion uses the shared Cable subscription once and keeps a deleted post in the feed", async () => {
  const editor = await mountDeletablePost()
  editor.button.click()
  editor.button.click()
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const [action, data] = requests[0].perform.mock.calls[0]
  expect(action).toBe("delete_message")
  expect(data).toEqual({ request_id: expect.any(String), message_id: 2 })
  expect(window.confirm).toHaveBeenCalledOnce()
  const deleted = deletionEvent(2)
  requests[0].callbacks.received(deleted)
  requests[0].callbacks.received({ ...deleted, type: "delete.saved", request_id: data.request_id })
  expect(editor.article.isConnected).toBe(true)
  expect(editor.body.textContent).toBe("Deleted post")
  expect(editor.article.querySelector("form, button")).toBeNull()
  expect(postIds()).toEqual(["2", "1"])
  expect(subscribeTo).toHaveBeenCalledOnce()
})

test("cancelling deletion sends no Cable write and preserves the open edit draft", async () => {
  const editor = await mountDeletablePost()
  vi.mocked(window.confirm).mockReturnValue(false)
  editor.edit.click()
  editor.input.value = "Keep my draft"
  editor.button.click()
  expect(requests[0].perform).not.toHaveBeenCalled()
  expect(editor.input.value).toBe("Keep my draft")
  expect(editor.body.textContent).toBe("Thought 2")
})

test("a rejected deletion unlocks controls without clearing the edit draft", async () => {
  const editor = await mountDeletablePost()
  editor.edit.click()
  editor.input.value = "Keep my draft"
  editor.button.click()
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]
  requests[0].callbacks.received({ type: "delete.rejected", request_id: data.request_id, error: "forbidden" })
  expect(editor.notice.textContent).toContain("permission to delete")
  expect(editor.input.value).toBe("Keep my draft")
  expect(editor.input.readOnly).toBe(false)
  expect(editor.button.disabled).toBe(false)
})

test("an unconfirmed deletion unlocks after five seconds without retrying", async () => {
  const editor = await mountDeletablePost()
  vi.useFakeTimers()
  editor.button.click()
  await Promise.resolve()
  await Promise.resolve()
  await vi.advanceTimersByTimeAsync(5_000)
  expect(editor.notice.textContent).toContain("could not be confirmed")
  expect(editor.button.disabled).toBe(false)
  expect(editor.body.textContent).toBe("Thought 2")
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("a deletion received during editing clears the draft and ignores later stale updates", async () => {
  const editor = await mountDeletablePost()
  editor.edit.click()
  editor.input.value = "Private draft"
  requests[0].callbacks.received(deletionEvent(2))
  expect(editor.input.value).toBe("")
  expect(editor.body.hidden).toBe(false)
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(2, "Stale body", "2026-10-21T12:01:00Z") })
  requests[0].callbacks.received(createdMessageEvent(2))
  requests[0].callbacks.received(deletionEvent(2))
  expect(editor.body.textContent).toBe("Deleted post")
  expect(editor.article.querySelector("form, button")).toBeNull()
})

test("owners and nonmember admins can see delete controls on others' live posts without an edit button", async () => {
  enableMessageEditing()
  enableMessageDeletion()
  element.dataset.clubDiscussionCanModerateValue = "true"
  element.dataset.clubDiscussionCanPostValue = "false"
  completeSetup(requests[0])
  await requests[0].promise
  requests[0].callbacks.received(createdMessageEvent(2))
  const article = messages.querySelector<HTMLElement>("#club_message_2")!
  expect(article.querySelector("[data-club-message-target='deleteButton']")).not.toBeNull()
  expect(article.querySelector("[data-club-message-target='editButton']")).toBeNull()
})

test("ordinary members cannot see delete controls for another author's live post", async () => {
  enableMessageEditing()
  enableMessageDeletion()
  completeSetup(requests[0])
  await requests[0].promise
  const created = createdMessageEvent(2)
  created.message.author.id = 99
  requests[0].callbacks.received(created)
  expect(messages.querySelector("#club_message_2 [data-club-message-target='deleteButton']")).toBeNull()
})

test("a deletion received before its create event renders only the deleted post", async () => {
  enableMessageEditing()
  enableMessageDeletion()
  completeSetup(requests[0])
  await requests[0].promise
  requests[0].callbacks.received(deletionEvent(2))
  requests[0].callbacks.received(createdMessageEvent(2))
  const article = messages.querySelector<HTMLElement>("#club_message_2")!
  expect(article.querySelector("p")!.textContent).toBe("Deleted post")
  expect(article.querySelector("button, form")).toBeNull()
})

test("a disconnected deletion unlocks controls and never retries after reconnection", async () => {
  const editor = await mountDeletablePost()
  editor.button.click()
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  requests[0].callbacks.disconnected({ willAttemptReconnect: true })
  expect(editor.notice.textContent).toContain("could not be confirmed")
  expect(editor.button.disabled).toBe(false)
  requests[0].callbacks.connected()
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("a failed deletion send preserves the message and reports an unconfirmed result", async () => {
  const editor = await mountDeletablePost()
  requests[0].perform.mockReturnValue(false)
  editor.button.click()
  await vi.waitFor(() => expect(editor.notice.textContent).toContain("could not be confirmed"))
  expect(editor.button.disabled).toBe(false)
  expect(editor.body.textContent).toBe("Thought 2")
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("a deleted post without replies disappears and updates the visible post total", async () => {
  const editor = await mountDeletablePost()
  const deleted = deletionEvent(2)
  deleted.message.replies_count = 0
  requests[0].callbacks.received({ ...deleted, total_posts: 1 })
  expect(editor.article.isConnected).toBe(false)
  expect(postIds()).toEqual(["1"])
  expect(element.querySelector("[data-club-discussion-target='paginationSummary']")!.textContent).toBe("1 post · Page 1 of 1")
  requests[0].callbacks.received(createdMessageEvent(2))
  expect(postIds()).toEqual(["1"])
})

test("a deleted post disappears after the final reply is deleted while earlier deletion events cannot restore it", async () => {
  const editor = await mountDeletablePost()
  const retained = deletionEvent(2)
  requests[0].callbacks.received({ ...retained, total_posts: 2 })
  expect(editor.article.isConnected).toBe(true)
  const empty = { ...retained.message, replies_count: 0, updated_at: "2026-10-21T12:01:00Z" }
  requests[0].callbacks.received({ type: "message.deleted", message: empty, total_posts: 1 })
  expect(editor.article.isConnected).toBe(false)
  requests[0].callbacks.received(retained)
  expect(postIds()).toEqual(["1"])
})

test("removing the last visible post displays the empty state", async () => {
  const editor = await mountDeletablePost()
  messages.querySelector("#club_message_1")!.remove()
  const deleted = deletionEvent(2)
  deleted.message.replies_count = 0
  requests[0].callbacks.received({ ...deleted, total_posts: 0 })
  expect(messages.childElementCount).toBe(0)
  expect(element.querySelector<HTMLElement>("[data-club-discussion-target='emptyState']")!.hidden).toBe(false)
})

test("the author can save an inline edit through the existing Cable connection", async () => {
  const editor = await mountEditablePost()
  editor.edit.click()
  expect(editor.input.value).toBe("Thought 2")
  expect(editor.body.hidden).toBe(true)
  editor.input.value = "Revised thought"
  submitComposer(editor.form)
  submitComposer(editor.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const [action, data] = requests[0].perform.mock.calls[0]
  expect(action).toBe("update_message")
  expect(data).toEqual({ request_id: expect.any(String), message_id: 2, body: "Revised thought" })
  expect(editor.input.readOnly).toBe(true)
  const message = editedMessage(2, "Revised thought")
  requests[0].callbacks.received({ type: "message.updated", message })
  requests[0].callbacks.received({ type: "edit.saved", request_id: data.request_id, message })
  expect(editor.body.textContent).toBe("Revised thought")
  expect(editor.form.hidden).toBe(true)
  expect(editor.body.hidden).toBe(false)
  expect(editor.notice.textContent).toBe("Changes saved.")
  expect(editor.input.value).toBe("")
  expect(subscribeTo).toHaveBeenCalledOnce()
})

test("cancel discards an edit draft and restores the published message", async () => {
  const editor = await mountEditablePost()
  editor.edit.click()
  editor.input.value = "Unwanted draft"
  editor.cancel.click()
  expect(editor.body.textContent).toBe("Thought 2")
  expect(editor.input.value).toBe("")
  expect(editor.form.hidden).toBe(true)
})

test("another author's live post has no editing controls", async () => {
  enableMessageEditing()
  const event = createdMessageEvent(3)
  event.message.author.id = 8
  requests[0].callbacks.received(event)
  const article = messages.querySelector<HTMLElement>("#club_message_3")!
  await vi.waitFor(() => expect(application.getControllerForElementAndIdentifier(article, "club-message")).not.toBeNull())
  expect(article.querySelector("[data-club-message-target='editButton']")).toBeNull()
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(3, "Someone else's revision") })
  expect(article.querySelector("[data-club-message-target='body']")!.textContent).toBe("Someone else's revision")
})

test.each([
  { error: "forbidden", text: "permission" },
  { error: "not_found", text: "no longer available" },
  { errors: { body: ["can't be blank"] }, text: "can't be blank" }
])("edit rejection preserves the draft: $text", async result => {
  const editor = await mountEditablePost()
  editor.edit.click()
  editor.input.value = "Keep this draft"
  submitComposer(editor.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]
  requests[0].callbacks.received({ type: "edit.rejected", request_id: data.request_id, ...result })
  expect(editor.input.value).toBe("Keep this draft")
  expect(editor.input.readOnly).toBe(false)
  expect(editor.form.hidden).toBe(false)
  expect(editor.notice.textContent).toContain(result.text)
})

test("duplicate and stale edits cannot replace newer text even within the same millisecond", async () => {
  const editor = await mountEditablePost()
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(2, "Newest", "2026-10-21T12:00:00.000002Z") })
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(2, "Older", "2026-10-21T12:00:00.000001Z") })
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(2, "Newest", "2026-10-21T12:00:00.000002Z") })
  expect(editor.body.textContent).toBe("Newest")
})

test("updated message bodies are displayed as text rather than executable markup", async () => {
  const editor = await mountEditablePost()
  const body = "<script>unsafe()</script><img src=x onerror=unsafe()>"
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(2, body) })
  expect(editor.body.textContent).toBe(body)
  expect(editor.body.querySelector("script, img")).toBeNull()
})

test("a remote update preserves an open edit draft and cancel reveals the latest text", async () => {
  const editor = await mountEditablePost()
  editor.edit.click()
  editor.input.value = "My draft"
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(2, "Changed elsewhere") })
  expect(editor.input.value).toBe("My draft")
  expect(editor.notice.textContent).toContain("changed elsewhere")
  editor.cancel.click()
  expect(editor.body.textContent).toBe("Changed elsewhere")
})

test("an update delivered before creation is retained when the message appears", async () => {
  enableMessageEditing()
  requests[0].callbacks.received({ type: "message.updated", message: editedMessage(2, "Updated before creation arrived") })
  requests[0].callbacks.received(createdMessageEvent(2))
  await vi.waitFor(() => expect(messages.querySelector("#club_message_2 [data-club-message-target='body']")!.textContent).toBe("Updated before creation arrived"))
})

test("disconnect and timeout preserve edit drafts without automatically retrying", async () => {
  const editor = await mountEditablePost()
  editor.edit.click()
  editor.input.value = "Keep this draft"
  vi.useFakeTimers()
  submitComposer(editor.form)
  await vi.advanceTimersByTimeAsync(20_000)
  expect(editor.input.value).toBe("Keep this draft")
  expect(editor.notice.textContent).toContain("could not be confirmed")
  expect(requests[0].perform).toHaveBeenCalledOnce()
  submitComposer(editor.form)
  await vi.advanceTimersByTimeAsync(0)
  requests[0].callbacks.disconnected({ willAttemptReconnect: true })
  expect(editor.input.value).toBe("Keep this draft")
  expect(editor.input.readOnly).toBe(false)
  expect(requests[0].perform).toHaveBeenCalledTimes(2)
})

test("a detached editor cannot send a delayed Cable write", async () => {
  const editor = await mountEditablePost()
  editor.edit.click()
  editor.input.value = "Detached draft"
  submitComposer(editor.form)
  editor.article.remove()
  await vi.waitFor(() => expect(application.getControllerForElementAndIdentifier(editor.article, "club-message")).toBeNull())
  expect(requests[0].perform).not.toHaveBeenCalled()
})

test("Turbo caching clears edit drafts and private message text", async () => {
  const editor = await mountEditablePost()
  editor.edit.click()
  editor.input.value = "Private edit draft"
  document.dispatchEvent(new Event("turbo:before-cache"))
  expect(editor.input.value).toBe("")
  expect(editor.body.textContent).toBe("")
  expect(content.childElementCount).toBe(0)
})

test("replies use the same inline editor and receive reply update broadcasts", async () => {
  enableMessageEditing()
  const composer = await mountReplyForm()
  requests[0].callbacks.received(replyEvent(8))
  const article = composer.controls.querySelector<HTMLElement>("#club_message_8")!
  await vi.waitFor(() => expect(article.querySelector("label")!.htmlFor).toBe("club_message_edit_8"))
  const editor = editingControls(article)
  editor.edit.click()
  editor.input.value = "Revised answer"
  submitComposer(editor.form)
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const data = requests[0].perform.mock.calls[0][1]
  expect(data.message_id).toBe(8)
  const message = { ...editedMessage(8, "Revised answer"), parent_id: 1 }
  requests[0].callbacks.received({ type: "reply.updated", message })
  requests[0].callbacks.received({ type: "edit.saved", request_id: data.request_id, message })
  expect(editor.body.textContent).toBe("Revised answer")
  expect(editor.form.hidden).toBe(true)
})

async function mountReplyForm(ready = true) {
  element.id = "club_discussion_17"
  application.register("club-replies", ClubRepliesController)
  const controls = document.createElement("div")
  controls.dataset.controller = "club-replies"
  controls.dataset.clubRepliesPostIdValue = "1"
  controls.dataset.clubRepliesClubDiscussionOutlet = "#club_discussion_17"
  controls.dataset.action = "club-discussion:reply@document->club-replies#receiveReply club-discussion:delete@document->club-replies#receiveDelete club-discussion:connection-ended@document->club-replies#connectionEnded turbo:before-cache@document->club-replies#beforeCache"
  controls.innerHTML = `<button data-club-replies-target="toggle" aria-expanded="true" data-action="club-replies#toggle"><span data-club-replies-target="countLabel">0 comments</span></button><div data-club-replies-target="panel"><div data-club-replies-target="list"></div><p data-club-replies-target="status"></p><button data-club-replies-target="more" hidden></button><form data-club-replies-target="form" data-action="submit->club-replies#postReply"><label data-club-replies-target="label">Your reply</label><textarea data-club-replies-target="body"></textarea><button type="submit" data-club-replies-target="submit">Reply</button><button type="button" data-club-replies-target="cancel" data-action="club-replies#cancelReply">Cancel</button><p data-club-replies-target="composerStatus"></p></form></div>`
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

test("deleting a post removes the reply composer but preserves existing replies and their edit controls", async () => {
  enableMessageEditing()
  enableMessageDeletion()
  const composer = await mountReplyForm()
  requests[0].callbacks.received(replyEvent(8))
  await vi.waitFor(() => expect(composer.controls.querySelector("#club_message_8 button")).not.toBeNull())
  composer.body.value = "Private reply draft"
  requests[0].callbacks.received(deletionEvent(1))
  expect(composer.form.isConnected).toBe(false)
  expect(composer.body.value).toBe("")
  expect(composer.controls.querySelector("#club_message_8")).not.toBeNull()
  expect(composer.controls.querySelector("#club_message_8 [data-club-message-target='editButton']")).not.toBeNull()
})

test("a deleted reply is removed and cannot be restored by delayed history or creation events", async () => {
  enableMessageEditing()
  enableMessageDeletion()
  const composer = await mountReplyForm()
  requests[0].callbacks.received(replyEvent(8))
  await vi.waitFor(() => expect(composer.controls.querySelector("#club_message_8 button")).not.toBeNull())
  const pending = Promise.withResolvers<Response>()
  vi.spyOn(globalThis, "fetch").mockReturnValue(pending.promise)
  const controller = application.getControllerForElementAndIdentifier(composer.controls, "club-replies") as ClubRepliesController
  const loading = controller.loadMore()
  requests[0].callbacks.received(deletionEvent(8, 1))
  expect(composer.controls.querySelector("#club_message_8")).toBeNull()
  pending.resolve(new Response(JSON.stringify({ replies: [ replyEvent(8).message ], pagination: { next_page: null } })))
  await loading
  requests[0].callbacks.received(replyEvent(8))
  expect(composer.controls.querySelector("#club_message_8")).toBeNull()
})

test("the reply author deletes through Cable and a saved acknowledgement removes the reply before its broadcast", async () => {
  enableMessageEditing()
  enableMessageDeletion()
  const composer = await mountReplyForm()
  requests[0].callbacks.received(replyEvent(8))
  const article = composer.controls.querySelector<HTMLElement>("#club_message_8")!
  await vi.waitFor(() => expect(article.querySelector("label")!.htmlFor).toBe("club_message_edit_8"))
  vi.spyOn(window, "confirm").mockReturnValue(true)
  article.querySelector<HTMLButtonElement>("[data-club-message-target='deleteButton']")!.click()
  await vi.waitFor(() => expect(requests[0].perform).toHaveBeenCalledOnce())
  const [action, data] = requests[0].perform.mock.calls[0]
  expect(action).toBe("delete_message")
  expect(data.message_id).toBe(8)
  const deleted = deletionEvent(8, 1)
  requests[0].callbacks.received({ ...deleted, type: "delete.saved", request_id: data.request_id })
  requests[0].callbacks.received(deleted)
  expect(composer.controls.querySelector("#club_message_8")).toBeNull()
  expect(messages.querySelector("#club_message_1")).not.toBeNull()
})

function replyEvent(id: number, type = "reply.created", requestId?: string) {
  const event = createdMessageEvent(id)
  event.type = type
  event.message.parent_id = 1
  return { ...event, request_id: requestId }
}

test("collapsed comment counts update for live creates and deletes without counting duplicate events", async () => {
  const composer = await mountReplyForm()
  const toggle = composer.controls.querySelector<HTMLButtonElement>("[data-club-replies-target='toggle']")!
  const label = composer.controls.querySelector("[data-club-replies-target='countLabel']")!
  toggle.click()
  expect(label.textContent).toBe("0 comments")

  requests[0].callbacks.received(replyEvent(8))
  requests[0].callbacks.received(replyEvent(8, "reply.saved"))
  expect(label.textContent).toBe("1 comment")
  requests[0].callbacks.received(replyEvent(9))
  expect(label.textContent).toBe("2 comments")

  requests[0].callbacks.received(deletionEvent(8, 1))
  requests[0].callbacks.received({ ...deletionEvent(8, 1), type: "delete.saved" })
  requests[0].callbacks.received(replyEvent(8))
  expect(label.textContent).toBe("1 comment")
  requests[0].callbacks.received(deletionEvent(9, 1))
  expect(label.textContent).toBe("0 comments")
  expect(toggle.getAttribute("aria-expanded")).toBe("false")
  expect(composer.controls.querySelector<HTMLElement>("[data-club-replies-target='panel']")!.hidden).toBe(true)
})

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
  expect(composer.controls.querySelector("[data-club-replies-target='countLabel']")!.textContent).toBe("1 comment")
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

test("missing reply acknowledgements show a notice after five seconds and preserve drafts without retrying", async () => {
  const composer = await mountReplyForm()
  vi.useFakeTimers()
  composer.body.value = "Keep this answer"
  submitComposer(composer.form)
  await vi.advanceTimersByTimeAsync(4_999)
  expect(composer.body.readOnly).toBe(true)
  expect(composer.notice.textContent).toBe("Posting reply…")
  await vi.advanceTimersByTimeAsync(1)
  expect(composer.body.readOnly).toBe(false)
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

test("a missing acknowledgement unlocks the draft after 5 seconds without retrying", async () => {
  const composer = await mountComposer()
  composer.body.value = "Unconfirmed"
  vi.useFakeTimers()

  submitComposer(composer.form)
  await Promise.resolve()
  await vi.advanceTimersByTimeAsync(4_999)
  expect(composer.body.readOnly).toBe(true)
  await vi.advanceTimersByTimeAsync(1)

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

test("heartbeat sends every ten seconds only after subscription confirmation", async () => {
  vi.useFakeTimers()
  completeSetup(requests[0])
  await vi.advanceTimersByTimeAsync(20_000)
  expect(requests[0].perform).not.toHaveBeenCalled()

  requests[0].callbacks.connected()
  await vi.advanceTimersByTimeAsync(9_999)
  expect(requests[0].perform).not.toHaveBeenCalled()
  await vi.advanceTimersByTimeAsync(1)
  expect(requests[0].perform).toHaveBeenCalledWith("heartbeat", {})
  await vi.advanceTimersByTimeAsync(10_000)
  expect(requests[0].perform).toHaveBeenCalledTimes(2)
})

test("temporary disconnection stops heartbeat and reconnection starts one interval", async () => {
  vi.useFakeTimers()
  completeSetup(requests[0])
  requests[0].callbacks.connected()
  await vi.advanceTimersByTimeAsync(10_000)
  requests[0].callbacks.disconnected({ willAttemptReconnect: true })
  await vi.advanceTimersByTimeAsync(30_000)
  expect(requests[0].perform).toHaveBeenCalledOnce()

  requests[0].callbacks.connected()
  requests[0].callbacks.connected()
  await vi.advanceTimersByTimeAsync(10_000)
  expect(requests[0].perform).toHaveBeenCalledTimes(2)
})

test("rejection and access revocation stop heartbeat", async () => {
  vi.useFakeTimers()
  completeSetup(requests[0])
  requests[0].callbacks.connected()
  requests[0].callbacks.received({ type: "access.revoked" })
  requests[0].callbacks.rejected()

  await vi.advanceTimersByTimeAsync(30_000)

  expect(requests[0].perform).not.toHaveBeenCalled()
})

test("Turbo navigation stops heartbeat", async () => {
  vi.useFakeTimers()
  completeSetup(requests[0])
  requests[0].callbacks.connected()
  document.dispatchEvent(new Event("turbo:before-cache"))

  await vi.advanceTimersByTimeAsync(30_000)

  expect(requests[0].perform).not.toHaveBeenCalled()
})

test("page removal cancels a heartbeat waiting for subscription setup", async () => {
  vi.useFakeTimers()
  requests[0].callbacks.connected()
  await vi.advanceTimersByTimeAsync(10_000)
  await removePage()
  completeSetup(requests[0])

  await vi.advanceTimersByTimeAsync(30_000)

  expect(requests[0].perform).not.toHaveBeenCalled()
  expect(requests[0].unsubscribe).toHaveBeenCalledOnce()
})

test("reconnection cancels an old heartbeat waiting for subscription setup", async () => {
  vi.useFakeTimers()
  requests[0].callbacks.connected()
  await vi.advanceTimersByTimeAsync(10_000)
  requests[0].callbacks.disconnected({ willAttemptReconnect: true })
  requests[0].callbacks.connected()
  completeSetup(requests[0])
  await vi.advanceTimersByTimeAsync(0)
  expect(requests[0].perform).not.toHaveBeenCalled()

  await vi.advanceTimersByTimeAsync(10_000)
  expect(requests[0].perform).toHaveBeenCalledOnce()
})

test("heartbeat send errors are reported and the next heartbeat can succeed", async () => {
  vi.useFakeTimers()
  const error = new Error("Heartbeat failed")
  const errorLog = vi.spyOn(console, "error").mockImplementation(() => {})
  requests[0].perform.mockImplementationOnce(() => { throw error })
  completeSetup(requests[0])
  requests[0].callbacks.connected()

  await vi.advanceTimersByTimeAsync(10_000)
  expect(errorLog).toHaveBeenCalledWith("Failed to send club presence heartbeat", error)
  await vi.advanceTimersByTimeAsync(10_000)
  expect(requests[0].perform).toHaveBeenCalledTimes(2)
})

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
  expect(post.querySelector(".club-discussion-message-meta .profile-avatar-initials")?.textContent).toBe("<I")
  expect(post.querySelector(".club-discussion-message-meta .profile-avatar-initials")?.getAttribute("aria-hidden")).toBe("true")
  expect(post.querySelector("strong")?.textContent).toBe(event.message.author.nickname)
  expect(post.querySelector("p")?.textContent).toBe(event.message.body)
  expect(post.querySelector("img, script")).toBeNull()
  expect(post.querySelector("time")?.getAttribute("datetime")).toBe(event.message.created_at)
  expect(post.querySelector("time")?.textContent).toBe("Oct 17, 2026 · 09:45")
})

test.each([
  { timestamp: "2026-10-17T00:05:00.000000Z", expected: "Oct 17, 2026 · 00:05" },
  { timestamp: "2026-10-17T13:45:00.000000Z", expected: "Oct 17, 2026 · 13:45" }
])("new posts display $timestamp as $expected without AM or PM", ({ timestamp, expected }) => {
  const event = createdMessageEvent(2)
  event.message.created_at = timestamp

  requests[0].callbacks.received(event)

  expect(document.querySelector("#club_message_2 time")?.textContent).toBe(expected)
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

test("live history retains only the latest 10 posts", () => {
  for (let id = 2; id <= 22; id += 1) {
    requests[0].callbacks.received(createdMessageEvent(id))
  }
  // A duplicate whose original element was removed must not be inserted again.
  requests[0].callbacks.received(createdMessageEvent(2))

  expect(messages.childElementCount).toBe(10)
  expect(postIds()[0]).toBe("22")
  expect(postIds()[9]).toBe("13")
  expect(element.querySelector("[data-club-discussion-target='paginationSummary']")?.textContent)
    .toBe("22 posts · Page 1 of 3")
})

test("crossing ten posts loads Rails-rendered Pagy controls and deleting back to ten removes them", async () => {
  element.dataset.clubDiscussionPaginationUrlValue = "/book_clubs/17/club_messages"
  await Promise.resolve()
  const http = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({
    pagination_html: '<nav class="pagy series-nav"><a href="/book_clubs/17/club_messages?page=2">2</a></nav>'
  })))
  for (let id = 2; id <= 11; id += 1) requests[0].callbacks.received(createdMessageEvent(id))

  await vi.waitFor(() => expect(element.querySelector("nav.pagy.series-nav a")?.textContent).toBe("2"))
  expect(http).toHaveBeenCalledOnce()
  expect(String(http.mock.calls[0][0])).toContain("page=1")
  expect(http.mock.calls[0][1]?.headers).toEqual({ Accept: "application/json" })

  const deleted = deletionEvent(11)
  deleted.message.replies_count = 0
  requests[0].callbacks.received({ ...deleted, total_posts: 10 })
  expect(element.querySelector("nav.pagy.series-nav")).toBeNull()
})

test("leaving the discussion aborts a pending pagination read and ignores its late response", async () => {
  element.dataset.clubDiscussionPaginationUrlValue = "/book_clubs/17/club_messages"
  await Promise.resolve()
  const pending = Promise.withResolvers<Response>()
  const http = vi.spyOn(globalThis, "fetch").mockReturnValue(pending.promise)
  const page = element.querySelector("[data-club-discussion-target='pagination']")!
  requests[0].callbacks.received({ ...createdMessageEvent(11), total_posts: 11 })
  const signal = http.mock.calls[0][1]!.signal!

  await removePage()
  expect(signal.aborted).toBe(true)
  pending.resolve(new Response(JSON.stringify({ pagination_html: '<nav class="pagy series-nav">Late controls</nav>' })))
  await pending.promise
  await Promise.resolve()
  expect(page.children).toHaveLength(0)
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
