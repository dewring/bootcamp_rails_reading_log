import { throttle } from "lodash"
import { buildUserAvatar } from "../helpers/user_avatar"
import { discussionVersion } from "./message_version"
import type { DiscussionEvent, DiscussionMember, DiscussionSubscription } from "./types"

interface PresenceTargets {
  onlineMembers?: HTMLUListElement
  presenceStatus?: HTMLElement
  typingStatus?: HTMLElement
  typingIndicator?: HTMLTemplateElement
}

interface PresenceOptions {
  root: HTMLElement
  currentUserId(): number
  canPost(): boolean
  targets(): PresenceTargets
}

export default class ClubPresence {
  private subscription?: Promise<DiscussionSubscription | undefined>
  private heartbeatInterval?: ReturnType<typeof setInterval>
  private snapshotTimeout?: ReturnType<typeof setTimeout>
  private latestPresenceVersion = ""
  private presenceAvailable = false
  private acceptingEvents = true
  private typingConnections = new Map<string, { member: DiscussionMember; timeout: ReturnType<typeof setTimeout>; version: string }>()
  private throttledTyping = throttle((source: HTMLTextAreaElement, pendingSubscription: Promise<DiscussionSubscription | undefined>, heartbeatInterval: ReturnType<typeof setInterval>) => {
    this.sendTyping(source, pendingSubscription, heartbeatInterval).catch(error => {
      console.error("Failed to send club typing event", error)
    })
  }, 1_000, { leading: true, trailing: false })

  constructor(private options: PresenceOptions) {
    this.showUnavailable()
  }

  subscriptionConfirmed(pendingSubscription: Promise<DiscussionSubscription | undefined>) {
    this.subscription = pendingSubscription
    this.acceptingEvents = true
    this.startHeartbeat(pendingSubscription)
  }

  receiveEvent(event: DiscussionEvent) {
    if (event.type === "presence.unavailable") {
      this.showUnavailable()
    } else if (this.acceptingEvents && event.type === "presence.snapshot") {
      this.receiveSnapshot(event)
    } else if (this.acceptingEvents && event.type === "typing.started") {
      this.receiveTyping(event)
    }
  }

  typing(event: Event) {
    const source = event.target
    if (!(source instanceof HTMLTextAreaElement) || source.disabled || source.readOnly || !source.value.trim()) return
    if (!this.options.canPost() || !this.subscription || !this.heartbeatInterval) return

    this.throttledTyping(source, this.subscription, this.heartbeatInterval)
  }

  disconnect() {
    this.stopHeartbeat()
    this.subscription = undefined
    this.acceptingEvents = false
    this.throttledTyping.cancel()
    this.showUnavailable()
  }

  private receiveSnapshot(event: DiscussionEvent) {
    if (!event.members || !event.generated_at || !Number.isFinite(Date.parse(event.generated_at))) return

    const version = discussionVersion(event.generated_at)
    if (version <= this.latestPresenceVersion) return

    this.latestPresenceVersion = version
    this.presenceAvailable = true
    const members = new Map(event.members.map(member => [member.id, member]))
    const targets = this.options.targets()
    if (targets.onlineMembers) {
      const orderedMembers = Array.from(members.values()).sort((first, second) => Number(second.id === this.options.currentUserId()) - Number(first.id === this.options.currentUserId()))
      const items = orderedMembers.map(member => this.buildMember(member))
      targets.onlineMembers.replaceChildren(...items)
      targets.onlineMembers.hidden = items.length === 0
    }
    if (targets.presenceStatus) {
      targets.presenceStatus.textContent = `${members.size} ${members.size === 1 ? "member" : "members"} online.`
      targets.presenceStatus.classList.add("club-discussion-sr-only")
    }
    for (const [token, connection] of this.typingConnections) {
      const member = members.get(connection.member.id)
      if (member) {
        connection.member = member
      } else {
        clearTimeout(connection.timeout)
        this.typingConnections.delete(token)
      }
    }
    this.renderTyping()
    clearTimeout(this.snapshotTimeout)
    this.snapshotTimeout = setTimeout(() => this.showUnavailable(), 55_000)
  }

  private buildMember(member: DiscussionMember): HTMLLIElement {
    const item = document.createElement("li")
    item.className = "club-presence-member"
    item.dataset.memberId = String(member.id)
    const avatar = buildUserAvatar(member)
    const details = document.createElement("span")
    details.className = "club-presence-details"
    const name = document.createElement("strong")
    name.textContent = member.nickname
    const status = document.createElement("span")
    status.className = "club-presence-member-status"
    details.append(name, status)
    item.append(avatar, details)
    return item
  }

  private receiveTyping(event: DiscussionEvent) {
    if (!this.presenceAvailable || !event.member || !event.connection_token || !event.generated_at) return

    const generatedAt = Date.parse(event.generated_at)
    if (!Number.isFinite(generatedAt) || Date.now() - generatedAt >= 3_000) return

    const token = event.connection_token
    const previous = this.typingConnections.get(token)
    const version = discussionVersion(event.generated_at)
    if (previous && version <= previous.version) return

    clearTimeout(previous?.timeout)
    const timeout = setTimeout(() => {
      this.typingConnections.delete(token)
      this.renderTyping()
    }, 3_000)
    this.typingConnections.set(token, { member: event.member, timeout, version })
    this.renderTyping()
  }

  private renderTyping() {
    const members = new Map(Array.from(this.typingConnections.values(), connection => [connection.member.id, connection.member]))
    const names = Array.from(members.values(), member => member.nickname)
    const targets = this.options.targets()
    if (targets.typingStatus) {
      const announcement = names.length === 0 ? "" : `${names.join(", ")} ${names.length === 1 ? "is" : "are"} typing…`
      if (targets.typingStatus.textContent !== announcement) targets.typingStatus.textContent = announcement
    }
    if (!targets.onlineMembers) return

    for (const item of Array.from(targets.onlineMembers.children)) {
      const memberId = Number((item as HTMLElement).dataset.memberId)
      const state = members.has(memberId) ? "Writing a post…" : memberId === this.options.currentUserId() ? "You" : "Online"
      const status = item.querySelector<HTMLElement>(".club-presence-member-status")
      if (!status || status.dataset.state === state) continue

      status.dataset.state = state
      status.replaceChildren()
      if (state === "Writing a post…" && targets.typingIndicator) {
        status.append(targets.typingIndicator.content.cloneNode(true))
      } else {
        status.textContent = state
      }
    }
  }

  private showUnavailable() {
    this.presenceAvailable = false
    clearTimeout(this.snapshotTimeout)
    this.snapshotTimeout = undefined
    for (const connection of this.typingConnections.values()) {
      clearTimeout(connection.timeout)
    }
    this.typingConnections.clear()
    this.renderTyping()
    const targets = this.options.targets()
    if (targets.onlineMembers) {
      targets.onlineMembers.replaceChildren()
      targets.onlineMembers.hidden = true
    }
    if (targets.presenceStatus) {
      targets.presenceStatus.textContent = "Presence unavailable"
      targets.presenceStatus.classList.remove("club-discussion-sr-only")
    }
  }

  private async sendTyping(source: HTMLTextAreaElement, pendingSubscription: Promise<DiscussionSubscription | undefined>, heartbeatInterval: ReturnType<typeof setInterval>) {
    const subscription = await pendingSubscription
    if (this.subscription !== pendingSubscription || this.heartbeatInterval !== heartbeatInterval) return
    if (!source.isConnected || !this.options.root.contains(source) || source.readOnly || source.disabled || !source.value.trim()) return

    subscription?.perform("typing", {})
  }

  private startHeartbeat(pendingSubscription: Promise<DiscussionSubscription | undefined>) {
    this.stopHeartbeat()
    const heartbeatInterval = setInterval(() => {
      this.sendHeartbeat(pendingSubscription, heartbeatInterval).catch(error => {
        console.error("Failed to send club presence heartbeat", error)
      })
    }, 10_000)
    this.heartbeatInterval = heartbeatInterval
  }

  private stopHeartbeat() {
    clearInterval(this.heartbeatInterval)
    this.heartbeatInterval = undefined
  }

  private async sendHeartbeat(pendingSubscription: Promise<DiscussionSubscription | undefined>, heartbeatInterval: ReturnType<typeof setInterval>) {
    const subscription = await pendingSubscription
    if (this.subscription !== pendingSubscription || this.heartbeatInterval !== heartbeatInterval) return

    subscription?.perform("heartbeat", {})
  }
}
