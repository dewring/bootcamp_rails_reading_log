import { Application } from "@hotwired/stimulus"
import { renderStreamMessage } from "@hotwired/turbo"
import { afterEach, expect, test, vi } from "vitest"
import ReactionPickerController from "../../app/javascript/controllers/reaction_picker_controller"

let application: Application | undefined

afterEach(() => {
  application?.stop()
  document.body.innerHTML = ""
})

test("live public totals update while trending scores ranks and card order stay unchanged", async () => {
  document.body.innerHTML = `
    <section class="home-trending">
      <div id="trending_book_1" class="home-trending-card">
        <p class="home-trending-rank">Rank 1</p>
        <a href="/books/1">First book</a>
        <p class="home-trending-score">7-day reactions: 2</p>
        <section data-controller="reaction-picker">
          <ul id="reaction_counts_book_1" hidden data-reaction-picker-target="counts">
            <li data-reaction-kind="like" data-count="2"></li>
          </ul>
          <ul><li data-reaction-picker-target="pill" data-kind="like" data-label="Like" data-selected="false">
            <span class="reaction-pill" aria-label="Like: 2"><span data-reaction-pill-count>2</span></span>
          </li></ul>
        </section>
      </div>
      <div id="trending_book_2" class="home-trending-card">
        <p class="home-trending-rank">Rank 2</p>
        <p class="home-trending-score">7-day reactions: 1</p>
      </div>
    </section>`
  application = Application.start()
  application.register("reaction-picker", ReactionPickerController)
  await vi.waitFor(() => expect(application?.getControllerForElementAndIdentifier(
    document.querySelector("[data-controller='reaction-picker']")!, "reaction-picker"
  )).toBeTruthy())
  const cards = Array.from(document.querySelectorAll(".home-trending-card"))
  const link = document.querySelector<HTMLAnchorElement>("a")!
  link.focus()

  renderStreamMessage(`<turbo-stream action="replace" target="reaction_counts_book_1"><template>
    <ul id="reaction_counts_book_1" hidden data-reaction-picker-target="counts">
      <li data-reaction-kind="like" data-count="0"></li>
    </ul>
  </template></turbo-stream>`)

  await vi.waitFor(() => expect(document.querySelector("[data-reaction-pill-count]")!.textContent).toBe("0"))
  expect(document.querySelector<HTMLElement>("[data-reaction-picker-target='pill']")!.hidden).toBe(true)
  expect(Array.from(document.querySelectorAll(".home-trending-card"))).toEqual(cards)
  expect(Array.from(document.querySelectorAll(".home-trending-rank")).map(node => node.textContent)).toEqual(["Rank 1", "Rank 2"])
  expect(Array.from(document.querySelectorAll(".home-trending-score")).map(node => node.textContent)).toEqual(["7-day reactions: 2", "7-day reactions: 1"])
  expect(document.activeElement).toBe(link)
})
