import { expect, test } from "vitest"
import { buildMessageElement, replaceReactionPanel } from "../../app/javascript/club_discussion/message_elements"
import type { DiscussionMessage } from "../../app/javascript/club_discussion/types"

const options = { rootId: "club_discussion_17", bookClubId: 17, currentUserId: 7, canPost: true, canModerate: false }
const message: DiscussionMessage = {
  id: 3, parent_id: null, body: "A public thought", author: { id: 7, nickname: "Reader" },
  created_at: "2026-10-21T12:00:00Z", updated_at: "2026-10-21T12:00:00Z"
}

test("a new live message loads its reaction panel from the authorized GET endpoint", () => {
  const article = buildMessageElement(message, options)
  const frame = article.querySelector("turbo-frame")!

  expect(frame.id).toBe("reaction_panel_club_message_3")
  expect(frame.getAttribute("src")).toBe("/book_clubs/17/club_messages/3/reaction")
  expect(frame.querySelector("[aria-pressed]")).toBeNull()
})

test("deleted live messages have no reaction frame", () => {
  const article = buildMessageElement({ ...message, deleted: true }, options)

  expect(article.querySelector(".reaction-panel")).toBeNull()
})

test("private history HTML replaces only the reaction frame and preserves the editor and reply drafts", () => {
  const article = buildMessageElement(message, options)
  const editor = document.createElement("textarea")
  editor.value = "Unsent edit"
  const reply = document.createElement("textarea")
  reply.value = "Unsent reply"
  article.append(editor, reply)
  const body = article.querySelector(".club-discussion-message-body")

  replaceReactionPanel(article, 3, '<turbo-frame id="reaction_panel_club_message_3" class="reaction-panel"><button aria-pressed="true">Like</button></turbo-frame>')

  expect(article.querySelector(".club-discussion-message-body")).toBe(body)
  expect(article.querySelector("turbo-frame")!.hasAttribute("src")).toBe(false)
  expect(article.querySelector("button[aria-pressed='true']")!.textContent).toBe("Like")
  expect(editor.value).toBe("Unsent edit")
  expect(reply.value).toBe("Unsent reply")
  expect(article.querySelectorAll("turbo-frame")).toHaveLength(1)
})
