import { test } from "node:test"
import assert from "node:assert/strict"
import { build } from "esbuild"

const bundle = await build({
  entryPoints: ["app/javascript/controllers/flash_notifications_controller.ts"],
  bundle: true,
  write: false,
  platform: "node",
  format: "esm"
})
const { default: FlashNotificationsController } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`
)

function notification(t, header = null) {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  const originalDocument = globalThis.document
  let headerQueries = 0
  let observedHeader
  let resize
  let observerDisconnects = 0
  const originalResizeObserver = globalThis.ResizeObserver
  globalThis.document = { querySelector: () => { headerQueries += 1; return header } }
  globalThis.ResizeObserver = class {
    constructor(callback) { resize = callback }
    observe(element) { observedHeader = element }
    disconnect() { observerDisconnects += 1 }
  }
  t.after(() => {
    if (originalDocument === undefined) delete globalThis.document
    else globalThis.document = originalDocument
    if (originalResizeObserver === undefined) delete globalThis.ResizeObserver
    else globalThis.ResizeObserver = originalResizeObserver
  })
  let removals = 0
  const element = { style: {}, remove: () => {
    removals += 1
    // Stimulus observes DOM removal and disconnects in the next microtask.
    queueMicrotask(() => controller.disconnect())
  } }
  const controller = new FlashNotificationsController({ scope: { element } })
  controller.connect()
  return {
    controller, element, removals: () => removals,
    headerQueries: () => headerQueries, observedHeader: () => observedHeader,
    resize: () => resize(), observerDisconnects: () => observerDisconnects
  }
}

test("notification stays visible until five seconds, then disappears", t => {
  const card = notification(t)
  t.mock.timers.tick(4999)
  assert.equal(card.removals(), 0)
  t.mock.timers.tick(1)
  assert.equal(card.removals(), 1)
  card.controller.disconnect()
})

test("closing the notification disconnects and cancels the pending dismissal", async t => {
  const closed = notification(t)
  closed.controller.clear()
  await Promise.resolve()
  t.mock.timers.tick(5000)
  assert.equal(closed.removals(), 1)
})

test("leaving the page cancels the pending dismissal", t => {
  const departed = notification(t)
  departed.controller.disconnect()
  t.mock.timers.tick(5000)
  assert.equal(departed.removals(), 0)
})


test("positioning reuses the observed header but reads its latest geometry", t => {
  let bottom = 64
  const header = { getBoundingClientRect: () => ({ bottom }) }
  const card = notification(t, header)
  assert.equal(card.observedHeader(), header)
  assert.equal(card.headerQueries(), 1)
  assert.equal(card.element.style.top, "76px")
  bottom = 96
  card.resize()
  assert.equal(card.element.style.top, "108px")
  bottom = -10
  card.controller.position()
  assert.equal(card.element.style.top, "12px")
  assert.equal(card.headerQueries(), 1)
  card.controller.disconnect()
  assert.equal(card.observerDisconnects(), 1)
})

test("positioning without a header keeps the twelve pixel fallback", t => {
  const card = notification(t)
  card.controller.position()
  assert.equal(card.element.style.top, "12px")
  assert.equal(card.headerQueries(), 1)
})

test("reconnecting looks up the current header again", t => {
  const card = notification(t, { getBoundingClientRect: () => ({ bottom: 64 }) })
  card.controller.disconnect()
  const replacement = { getBoundingClientRect: () => ({ bottom: 120 }) }
  document.querySelector = () => replacement
  card.controller.connect()
  assert.equal(card.observedHeader(), replacement)
  assert.equal(card.element.style.top, "132px")
  card.controller.disconnect()
})
