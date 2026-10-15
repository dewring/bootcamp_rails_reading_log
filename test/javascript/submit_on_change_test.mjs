import { test } from "node:test"
import assert from "node:assert/strict"
import { build } from "esbuild"

const bundle = await build({
  entryPoints: ["app/javascript/controllers/submit_on_change_controller.ts"],
  bundle: true, write: false, platform: "node", format: "esm"
})
const { default: SubmitOnChangeController } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`
)

function submission(t, hasForm = true) {
  const originalInput = globalThis.HTMLInputElement
  globalThis.HTMLInputElement = class {
    constructor(type, files) { this.type = type; this.files = files }
  }
  t.after(() => {
    if (originalInput === undefined) delete globalThis.HTMLInputElement
    else globalThis.HTMLInputElement = originalInput
  })
  let submissions = 0
  const form = { requestSubmit: () => { submissions += 1 } }
  const element = { closest: selector => {
    assert.equal(selector, "form")
    return hasForm ? form : null
  } }
  const controller = new SubmitOnChangeController({ scope: { element } })
  return { controller, count: () => submissions }
}

test("choosing a profile photo submits its containing form", t => {
  const state = submission(t)
  state.controller.submit({ target: new HTMLInputElement("file", [{}]) })
  assert.equal(state.count(), 1)
})

test("cancelling a file selection does not submit the form", t => {
  const state = submission(t)
  state.controller.submit({ target: new HTMLInputElement("file", []) })
  state.controller.submit({ target: new HTMLInputElement("file", null) })
  assert.equal(state.count(), 0)
})

test("ordinary select and text changes still submit the form", t => {
  const state = submission(t)
  state.controller.submit({ target: { tagName: "SELECT", value: "reading" } })
  state.controller.submit({ target: new HTMLInputElement("text", null) })
  assert.equal(state.count(), 2)
})

test("a control without a containing form does not throw", t => {
  const state = submission(t, false)
  assert.doesNotThrow(() => state.controller.submit({ target: { tagName: "SELECT" } }))
  assert.equal(state.count(), 0)
})
