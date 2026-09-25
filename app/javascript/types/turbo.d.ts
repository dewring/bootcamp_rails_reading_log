declare module "@hotwired/turbo" {
  export function renderStreamMessage(message: string): void
}

declare module "@hotwired/turbo-rails" {
  interface CableSubscription {
    unsubscribe(): void
  }

  interface Cable {
    subscribeTo(
      channel: string,
      callbacks: { received(message: string): void }
    ): Promise<CableSubscription>
  }

  export const cable: Cable
}
