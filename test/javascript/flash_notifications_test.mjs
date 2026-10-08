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

function notification(t) {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  const originalDocument = globalThis.document
  globalThis.document = { querySelector: () => null }
  t.after(() => {
    if (originalDocument === undefined) delete globalThis.document
    else globalThis.document = originalDocument
  })
  let removals = 0
  const element = { style: {}, remove: () => { removals += 1 } }
  const controller = new FlashNotificationsController({ scope: { element } })
  controller.connect()
  return { controller, removals: () => removals }
}

test("notification stays visible until five seconds, then disappears", t => {
  const card = notification(t)
  t.mock.timers.tick(4999)
  assert.equal(card.removals(), 0)
  t.mock.timers.tick(1)
  assert.equal(card.removals(), 1)
  card.controller.disconnect()
})

test("closing the notification cancels the pending dismissal", t => {
  const closed = notification(t)
  closed.controller.clear()
  t.mock.timers.tick(5000)
  assert.equal(closed.removals(), 1)
})

test("leaving the page cancels the pending dismissal", t => {
  const departed = notification(t)
  departed.controller.disconnect()
  t.mock.timers.tick(5000)
  assert.equal(departed.removals(), 0)
})
