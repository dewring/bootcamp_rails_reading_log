import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, expect, test, vi } from "vitest"
import ReactionPickerController from "../../app/javascript/controllers/reaction_picker_controller"

let application: Application
let element: HTMLElement

beforeEach(async () => {
  element = document.createElement("section")
  element.dataset.controller = "reaction-picker"
  element.dataset.action = "click@document->reaction-picker#closeOutside keydown.esc@document->reaction-picker#close"
  element.innerHTML = `
    <ul hidden data-reaction-picker-target="counts"><li data-reaction-kind="like" data-count="1"></li></ul>
    <ul>
      <li data-reaction-picker-target="pill" data-kind="like" data-label="Like" data-selected="true">
        <form><input name="_method" value="delete"><button class="reaction-pill" aria-pressed="true"><span data-reaction-pill-count>1</span></button></form>
      </li>
      <li data-reaction-picker-target="pill" data-kind="wow" data-label="Wow" data-selected="false">
        <button class="reaction-pill" aria-pressed="false"><span data-reaction-pill-count>0</span></button>
      </li>
    </ul>
    <details data-reaction-picker-target="picker"><summary>Add a Reaction</summary><button>Wow</button></details>
    <textarea>Unsent draft</textarea>`
  document.body.append(element)
  application = Application.start()
  application.register("reaction-picker", ReactionPickerController)
  await vi.waitFor(() => expect(element.querySelector<HTMLElement>("[data-kind='wow']")!.hidden).toBe(true))
})

afterEach(() => {
  element.remove()
  application.stop()
})

test("live totals reveal new pills without replacing private selection forms or drafts", async () => {
  const selected = element.querySelector("form")!
  const counts = document.createElement("ul")
  counts.dataset.reactionPickerTarget = "counts"
  counts.innerHTML = '<li data-reaction-kind="wow" data-count="3"></li>'
  element.querySelector("[data-reaction-picker-target='counts']")!.replaceWith(counts)

  await vi.waitFor(() => expect(element.querySelector("[data-kind='wow'] [data-reaction-pill-count]")!.textContent).toBe("3"))
  expect(element.querySelector<HTMLElement>("[data-kind='wow']")!.hidden).toBe(false)
  expect(element.querySelector("[data-kind='wow'] button")!.getAttribute("aria-label")).toBe("Wow: 3")
  expect(element.querySelector<HTMLElement>("[data-kind='like']")!.hidden).toBe(false)
  expect(element.querySelector("[data-kind='like'] [data-reaction-pill-count]")!.textContent).toBe("0")
  expect(element.querySelector("form")).toBe(selected)
  expect(selected.querySelector("input")!.value).toBe("delete")
  expect(selected.querySelector("button")!.getAttribute("aria-pressed")).toBe("true")
  expect(element.querySelector("textarea")!.value).toBe("Unsent draft")
})

test("outside clicks close the picker and Escape returns focus to its native disclosure", () => {
  const picker = element.querySelector("details")!
  picker.open = true
  picker.querySelector("button")!.dispatchEvent(new MouseEvent("click", { bubbles: true }))
  expect(picker.open).toBe(true)
  document.body.click()
  expect(picker.open).toBe(false)

  picker.open = true
  picker.querySelector("button")!.focus()
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
  expect(picker.open).toBe(false)
  expect(document.activeElement).toBe(picker.querySelector("summary"))
})

test("read-only panels update without requiring a picker", async () => {
  element.querySelector("details")!.remove()
  await Promise.resolve()
  document.body.click()
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
  expect(element.querySelector("textarea")!.value).toBe("Unsent draft")
})
