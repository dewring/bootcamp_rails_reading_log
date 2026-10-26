export interface DiscussionMessage {
  id: number
  parent_id: number | null
  body: string
  replies_count?: number
  deleted?: boolean
  author: { id: number; nickname: string; avatar_url?: string | null }
  created_at: string
  updated_at: string
}

export interface DiscussionMember {
  id: number
  nickname: string
  avatar_url?: string | null
}

export interface DiscussionEvent {
  type: string
  message?: DiscussionMessage
  total_posts?: number
  request_id?: string
  errors?: { body?: string[] }
  error?: string
  members?: DiscussionMember[]
  member?: DiscussionMember
  connection_token?: string
  generated_at?: string
}

export type DiscussionSubscription = {
  unsubscribe(): void
  perform(action: string, data: { request_id?: string; body?: string; parent_id?: number; message_id?: number }): boolean
}

export interface DiscussionHistory {
  messages: DiscussionMessage[]
  total_posts: number
  pagination_html: string
}

