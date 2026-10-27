import { buildUserAvatar } from "../helpers/user_avatar"
import type { DiscussionMessage } from "./types"

export interface MessageElementOptions {
  rootId: string
  bookClubId: number
  currentUserId: number
  canPost: boolean
  canModerate: boolean
  editor?: HTMLTemplateElement
  deleteButton?: HTMLTemplateElement
  replyControls?: HTMLTemplateElement
}

export function prepareMessageElement(article: HTMLElement, message: Pick<DiscussionMessage, "id" | "updated_at" | "deleted"> & { author: { id: number } }, options: MessageElementOptions) {
  const body = article.querySelector<HTMLElement>(".club-discussion-message-body, .club-discussion-reply-body")
  if (!body) return

  article.dataset.deleted = String(message.deleted ?? false)
  article.dataset.controller = "club-message"
  article.dataset.clubMessageMessageIdValue = String(message.id)
  article.dataset.clubMessageUpdatedAtValue = message.updated_at
  article.dataset.clubMessageClubDiscussionOutlet = `#${options.rootId}`
  article.dataset.action = "club-discussion:edit@document->club-message#receiveEdit club-discussion:delete@document->club-message#receiveDelete club-discussion:connection-ended@document->club-message#connectionEnded turbo:before-cache@document->club-message#beforeCache"
  body.dataset.clubMessageTarget = "body"
  if (!message.deleted && options.canPost && message.author.id === options.currentUserId && options.editor) {
    if (!article.querySelector("[data-club-message-target='form']")) article.append(options.editor.content.cloneNode(true))
  }
  const canDelete = options.canModerate || (options.canPost && message.author.id === options.currentUserId)
  if (!message.deleted && canDelete && options.deleteButton) {
    article.classList.add("club-message-moderatable")
    if (!article.querySelector("[data-club-message-target='deleteButton']")) article.append(options.deleteButton.content.cloneNode(true))
  }
  if (!article.querySelector("[data-club-message-target='status']")) {
    const status = document.createElement("p")
    status.setAttribute("role", "status")
    status.dataset.clubMessageTarget = "status"
    status.className = "club-message-edit-status"
    const editor = article.querySelector(".club-message-editor")
    if (editor) editor.append(status)
    else article.append(status)
  }
}

export function buildMessageElement(message: DiscussionMessage, options: MessageElementOptions) {
  const article = document.createElement("article")
  article.id = `club_message_${message.id}`
  article.dataset.messageId = String(message.id)
  article.dataset.authorId = String(message.author.id)
  article.dataset.updatedAt = message.updated_at
  article.className = "club-discussion-message"

  const header = document.createElement("header")
  header.className = "club-discussion-message-meta"
  const author = document.createElement("strong")
  author.textContent = message.author.nickname
  const time = document.createElement("time")
  time.dateTime = message.created_at
  const createdAt = new Date(message.created_at)
  const dateText = createdAt.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" })
  const timeText = createdAt.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZone: "UTC" })
  time.textContent = `${dateText} · ${timeText}`
  header.append(buildUserAvatar(message.author), author, time)

  const body = document.createElement("p")
  body.className = "club-discussion-message-body"
  body.textContent = message.deleted ? "Deleted post" : message.body
  article.append(header, body)
  prepareMessageElement(article, message, options)
  if (options.replyControls) {
    const controls = options.replyControls.content.firstElementChild!.cloneNode(true) as HTMLElement
    controls.dataset.clubRepliesPostIdValue = String(message.id)
    controls.dataset.clubRepliesUrlValue = `/book_clubs/${options.bookClubId}/club_messages/${message.id}/replies`
    controls.dataset.clubRepliesDeletedValue = String(message.deleted ?? false)
    controls.dataset.clubRepliesCountValue = String(message.replies_count ?? 0)
    article.append(controls)
  }
  return article
}
