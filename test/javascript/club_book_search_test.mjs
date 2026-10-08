import { test } from "node:test"
import assert from "node:assert/strict"
import { build } from "esbuild"

const bundle = await build({
  entryPoints: ["app/javascript/controllers/club_book_search_controller.ts"],
  bundle: true, write: false, platform: "node", format: "esm"
})
const { default: ClubBookSearchController } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`
)

function bookSearch(t) {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  const requests = []
  t.mock.method(globalThis, "fetch", (url, { signal }) => new Promise(resolve => {
    requests.push({ url, signal, resolve })
  }))
  const controller = new ClubBookSearchController({ scope: { element: {} } })
  const attributes = new Map()
  const search = {
    value: "Original · Author", validity: "",
    setCustomValidity(message) { this.validity = message },
    setAttribute(name, value) { attributes.set(name, value) },
    removeAttribute(name) { attributes.delete(name) }
  }
  const results = { hidden: false }
  const value = { value: "5" }
  const status = { textContent: "" }
  Object.assign(controller, {
    searchTarget: search, resultsTarget: results, valueTarget: value,
    statusTarget: status, urlValue: "/admin/books/search"
  })
  controller.connect()
  t.after(() => controller.disconnect())
  return { controller, search, results, value, status, attributes, requests }
}

test("changing the query cancels the previous debounce and searches only the latest input", t => {
  const state = bookSearch(t)
  state.search.value = "Old title"
  state.controller.search()
  t.mock.timers.tick(200)
  state.search.value = "New title"
  state.controller.search()
  t.mock.timers.tick(299)
  assert.equal(state.requests.length, 0)
  t.mock.timers.tick(1)
  assert.equal(state.requests.length, 1)
  assert.equal(state.requests[0].url, "/admin/books/search?q=New%20title")
  assert.equal(state.results.hidden, true)
  assert.equal(state.attributes.get("aria-expanded"), "false")
})

test("clearing the input aborts an in-flight search and ignores its late response", async t => {
  const state = bookSearch(t)
  state.search.value = "Book"
  state.controller.search()
  t.mock.timers.tick(300)
  const request = state.requests[0]
  state.search.value = ""
  state.controller.search()
  assert.equal(request.signal.aborted, true)
  assert.equal(state.search.validity, "")
  assert.equal(state.value.value, "")
  assert.equal(state.status.textContent, "No current pick")
  request.resolve({ ok: true, json: async () => ({ books: [{ id: 1, title: "Book", author: "Author" }] }) })
  await Promise.resolve()
  await Promise.resolve()
  await Promise.resolve()
  t.mock.timers.tick(300)
  assert.equal(state.requests.length, 1)
  assert.equal(state.results.hidden, true)
  assert.equal(state.status.textContent, "No current pick")
})
