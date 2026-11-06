declare module "@hotwired/turbo" {
  export function renderStreamMessage(message: string): void
}

declare module "@hotwired/turbo-rails" {
  interface CableSubscription {
    unsubscribe(): void
    perform(action: string, data?: object): boolean
  }

  interface Cable {
    subscribeTo<Message>(
      channel: string | { channel: string; book_club_id: number } | { channel: string; signed_stream_name: string },
      callbacks: {
        received(message: Message): void
        connected?(): void
        rejected?(): void
        disconnected?(details: { willAttemptReconnect: boolean }): void
      }
    ): Promise<CableSubscription>
  }

  export const cable: Cable
}
