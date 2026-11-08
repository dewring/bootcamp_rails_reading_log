import { renderStreamMessage } from "@hotwired/turbo"
import { afterEach, expect, test, vi } from "vitest"

afterEach(() => {
  document.body.innerHTML = ""
})

test("a current pick stream preserves post edit and reply drafts and does not request scrolling", async () => {
  document.body.innerHTML = `
    <article id="current_pick_book_club_17"><h2>Old book</h2></article>
    <form><textarea id="post-draft"></textarea></form>
    <form><textarea id="edit-draft"></textarea></form>
    <form><textarea id="reply-draft"></textarea></form>
  `
  const drafts = Array.from(document.querySelectorAll("textarea"))
  drafts.forEach((input, index) => {
    input.value = `Unfinished draft ${index}`
  })
  const reply = drafts[2]
  reply.focus()
  reply.setSelectionRange(3, 7)
  const scrollTo = vi.spyOn(window, "scrollTo")

  renderStreamMessage(`<turbo-stream action="replace" target="current_pick_book_club_17">
    <template><article id="current_pick_book_club_17"><h2>New book</h2>
      <p>Reading deadline: <time datetime="2026-12-15">December 15, 2026</time></p>
    </article></template>
  </turbo-stream>`)

  await vi.waitFor(() => {
    expect(document.querySelector("#current_pick_book_club_17 h2")?.textContent).toBe("New book")
  })
  expect(document.querySelector("time")?.dateTime).toBe("2026-12-15")
  drafts.forEach((input, index) => {
    expect(document.getElementById(input.id)).toBe(input)
    expect(input.value).toBe(`Unfinished draft ${index}`)
  })
  expect(document.activeElement).toBe(reply)
  expect([reply.selectionStart, reply.selectionEnd]).toEqual([3, 7])
  expect(scrollTo).not.toHaveBeenCalled()
})
