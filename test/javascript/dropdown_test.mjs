import { test } from "node:test"
import assert from "node:assert/strict"
import { build } from "esbuild"

const bundle = await build({
  stdin: {
    contents: `export { default as NavDropdownController } from "./app/javascript/controllers/nav_dropdown_controller";
      export { default as SelectDropdownController } from "./app/javascript/controllers/select_dropdown_controller";
      export { default as NotificationDropdownController } from "./app/javascript/controllers/notification_dropdown_controller";`,
    resolveDir: process.cwd()
  },
  bundle: true,
  write: false,
  platform: "node",
  format: "esm",
  plugins: [{
    name: "notification-transport-test-double",
    setup(build) {
      build.onResolve({ filter: /^@hotwired\/turbo(-rails)?$/ }, args => ({ path: args.path, namespace: "test-transport" }))
      build.onLoad({ filter: /.*/, namespace: "test-transport" }, args => ({
        contents: args.path === "@hotwired/turbo"
          ? "export const renderStreamMessage = message => globalThis.dropdownTransport.received.push(message)"
          : "export const cable = { subscribeTo: (...args) => globalThis.dropdownTransport.subscribeTo(...args) }"
      }))
    }
  }]
})
const { NavDropdownController, NotificationDropdownController, SelectDropdownController } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`
)

function dropdown(t, Controller, subscribeTo = async () => ({ unsubscribe() {} })) {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  const originals = new Map(["document", "window", "dropdownTransport"].map(key => [key, globalThis[key]]))
  globalThis.document = new EventTarget()
  globalThis.window = Object.assign(new EventTarget(), {
    setTimeout: (...args) => setTimeout(...args),
    clearTimeout: id => clearTimeout(id)
  })
  globalThis.dropdownTransport = { subscribeTo, received: [] }
  const inside = {}
  const element = { contains: target => target === inside }
  const controller = new Controller({ scope: { element } })
  const menu = { hidden: true }
  let expanded = "false"
  let focusCount = 0
  const trigger = {
    setAttribute: (_, value) => { expanded = value },
    focus: () => { focusCount += 1 }
  }
  Object.assign(controller, { menuTarget: menu, triggerTarget: trigger })
  // These unit tests construct controllers without a mounted Stimulus application.
  // Model its Boolean value accessor and deliver the value-change callback directly.
  let open = false
  Object.defineProperty(controller, "openValue", {
    get: () => open,
    set: value => {
      if (open === value) return
      open = value
      controller.openValueChanged()
    }
  })
  controller.openValueChanged()
  controller.connect()
  t.after(() => {
    controller.disconnect()
    for (const [key, value] of originals) {
      if (value === undefined) delete globalThis[key]
      else globalThis[key] = value
    }
  })
  return { controller, menu, trigger, inside, expanded: () => expanded, focusCount: () => focusCount }
}

for (const [name, Controller] of [["account/navigation", NavDropdownController], ["notifications", NotificationDropdownController]]) {
  test(`${name}: value state controls the menu independently of rendered ARIA`, t => {
    const menu = dropdown(t, Controller)
    assert.equal(menu.controller.openValue, false)
    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.expanded(), "false")
    menu.trigger.setAttribute("aria-expanded", "true")
    menu.controller.toggle()
    assert.equal(menu.controller.openValue, true)
    assert.equal(menu.menu.hidden, false)
    menu.controller.openValue = false
    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.expanded(), "false")
  })

  test(`${name}: clicking toggles visibility and accessibility state`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.toggle()
    assert.equal(menu.menu.hidden, false)
    assert.equal(menu.expanded(), "true")
    menu.controller.toggle()
    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.expanded(), "false")
  })

  test(`${name}: outside click closes while inside click keeps the menu open`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.toggle()
    menu.controller.closeOnOutsideClick({ target: menu.inside })
    assert.equal(menu.menu.hidden, false)
    menu.controller.closeOnOutsideClick({ target: {} })
    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.expanded(), "false")
  })

  test(`${name}: clicking after mouseenter and focusin closes and reopens the menu`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.enter()
    menu.controller.focusIn()
    assert.equal(menu.menu.hidden, false)

    menu.controller.toggle()
    menu.controller.closeOnOutsideClick({ target: menu.inside })
    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.expanded(), "false")

    menu.controller.toggle()
    assert.equal(menu.menu.hidden, false)
    assert.equal(menu.expanded(), "true")
  })

  test(`${name}: keyboard activation toggles while the trigger remains focused`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.focusIn()
    assert.equal(menu.menu.hidden, false)

    menu.controller.toggle()
    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.expanded(), "false")

    menu.controller.toggle()
    assert.equal(menu.menu.hidden, false)
    assert.equal(menu.expanded(), "true")
  })

  test(`${name}: Escape closes and returns focus to the trigger`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.toggle()
    menu.controller.closeOnEscape()
    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.focusCount(), 1)
    menu.controller.closeOnEscape()
    assert.equal(menu.focusCount(), 1)
    menu.controller.focusIn()
    assert.equal(menu.menu.hidden, false)
  })

  test(`${name}: Escape refocus does not reopen but later keyboard focus does`, t => {
    const menu = dropdown(t, Controller)
    const openedEvents = []
    window.addEventListener("dropdown:opened", event => openedEvents.push(event))
    const focus = menu.trigger.focus
    t.mock.method(menu.trigger, "focus", () => {
      focus()
      menu.controller.focusOut()
      menu.controller.focusIn()
    })
    menu.controller.focusIn()
    assert.equal(menu.menu.hidden, false)
    assert.equal(openedEvents.length, 1)

    menu.controller.closeOnEscape()

    assert.equal(menu.menu.hidden, true)
    assert.equal(menu.expanded(), "false")
    assert.equal(menu.focusCount(), 1)
    assert.equal(openedEvents.length, 1)
    t.mock.timers.tick(150)
    assert.equal(menu.menu.hidden, true)

    menu.controller.focusOut()
    t.mock.timers.tick(150)
    menu.controller.focusIn()
    assert.equal(menu.menu.hidden, false)
    assert.equal(menu.expanded(), "true")
    assert.equal(openedEvents.length, 2)
  })

  test(`${name}: hovering opens and reentering cancels a delayed close`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.enter()
    assert.equal(menu.menu.hidden, false)
    menu.controller.leave()
    t.mock.timers.tick(149)
    assert.equal(menu.menu.hidden, false)
    menu.controller.enter()
    t.mock.timers.tick(150)
    assert.equal(menu.menu.hidden, false)
    menu.controller.leave()
    t.mock.timers.tick(150)
    assert.equal(menu.menu.hidden, true)
  })

  test(`${name}: focus keeps the menu open after the pointer leaves`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.enter()
    menu.controller.focusIn()
    menu.controller.leave()
    t.mock.timers.tick(150)
    assert.equal(menu.menu.hidden, false)
    menu.controller.focusOut()
    t.mock.timers.tick(150)
    assert.equal(menu.menu.hidden, true)
  })

  test(`${name}: another dropdown closes this menu but its own event does not`, t => {
    const menu = dropdown(t, Controller)
    let openedEvent
    window.addEventListener("dropdown:opened", event => {
      openedEvent = event
      menu.controller.closeIfAnother(event)
    })
    menu.controller.enter()
    assert.equal(openedEvent.type, "dropdown:opened")
    assert.equal(openedEvent.target, window)
    assert.equal(openedEvent.detail.source, menu.controller.element)
    assert.equal(menu.menu.hidden, false)
    window.dispatchEvent(new CustomEvent("dropdown:opened", { detail: { source: {} } }))
    assert.equal(menu.menu.hidden, true)
    menu.controller.toggle()
    assert.equal(menu.menu.hidden, false)
  })

  test(`${name}: disconnect cancels delayed closing`, t => {
    const menu = dropdown(t, Controller)
    menu.controller.enter()
    menu.controller.leave()
    menu.controller.disconnect()
    t.mock.timers.tick(150)
    assert.equal(menu.menu.hidden, false)
    assert.equal(menu.focusCount(), 0)
  })
}

test("notifications: reconnect disposes late subscriptions and keeps the current stream", async t => {
  const subscriptions = []
  const menu = dropdown(t, NotificationDropdownController, (channel, callbacks) => {
    assert.equal(channel, "Noticed::NotificationChannel")
    return new Promise(resolve => subscriptions.push({ resolve, callbacks }))
  })
  menu.controller.disconnect()
  menu.controller.connect()
  let oldUnsubscribed = 0
  let currentUnsubscribed = 0
  subscriptions[1].resolve({ unsubscribe: () => { currentUnsubscribed += 1 } })
  subscriptions[0].resolve({ unsubscribe: () => { oldUnsubscribed += 1 } })
  await Promise.resolve()
  await Promise.resolve()
  assert.equal(oldUnsubscribed, 1)
  assert.equal(currentUnsubscribed, 0)
  subscriptions[1].callbacks.received("<turbo-stream></turbo-stream>")
  assert.deepEqual(dropdownTransport.received, ["<turbo-stream></turbo-stream>"])
  menu.controller.disconnect()
  assert.equal(currentUnsubscribed, 1)
})

test("notifications: subscription failure is reported", async t => {
  const error = new Error("Connection failed")
  const report = t.mock.method(console, "error", () => {})
  dropdown(t, NotificationDropdownController, async () => { throw error })
  await Promise.resolve()
  await Promise.resolve()
  assert.equal(report.mock.callCount(), 1)
  assert.equal(report.mock.calls[0].arguments[1], error)
})


test("select: value state toggles visibility and outside click closes", t => {
  const menu = dropdown(t, SelectDropdownController)
  assert.equal(menu.menu.hidden, true)
  assert.equal(menu.expanded(), "false")
  menu.trigger.setAttribute("aria-expanded", "true")
  menu.controller.toggle()
  assert.equal(menu.controller.openValue, true)
  assert.equal(menu.menu.hidden, false)
  menu.controller.closeUnlessInside({ target: menu.inside })
  assert.equal(menu.controller.openValue, true)
  menu.controller.closeUnlessInside({ target: {} })
  assert.equal(menu.menu.hidden, true)
  assert.equal(menu.expanded(), "false")
  menu.controller.toggle()
  menu.controller.close()
  assert.equal(menu.controller.openValue, false)
  assert.equal(menu.menu.hidden, true)
})

test("select: selecting updates the field and label, closes, and restores focus", t => {
  const menu = dropdown(t, SelectDropdownController)
  const option = text => ({
    textContent: text,
    classList: { toggle: (_, selected) => {} },
    setAttribute(name, value) { this[name] = value }
  })
  const first = option("Active")
  const second = option(" Invited ")
  const value = { value: "active" }
  const label = { textContent: "Active" }
  Object.assign(menu.controller, { valueTarget: value, labelTarget: label, optionTargets: [first, second] })
  menu.controller.toggle()
  menu.controller.select({ currentTarget: second, params: { value: "invited" } })
  assert.equal(value.value, "invited")
  assert.equal(label.textContent, "Invited")
  assert.equal(first["aria-selected"], "false")
  assert.equal(second["aria-selected"], "true")
  assert.equal(menu.controller.openValue, false)
  assert.equal(menu.menu.hidden, true)
  assert.equal(menu.expanded(), "false")
  assert.equal(menu.focusCount(), 1)
})


for (const value of [false, true, 0, 42]) {
  test(`select: typed action parameter ${value} is saved as form text`, t => {
    const menu = dropdown(t, SelectDropdownController)
    const option = { textContent: String(value), classList: { toggle() {} }, setAttribute() {} }
    const field = { value: "" }
    Object.assign(menu.controller, { valueTarget: field, labelTarget: {}, optionTargets: [option] })
    menu.controller.select({ currentTarget: option, params: { value } })
    assert.equal(field.value, String(value))
    assert.equal(menu.controller.openValue, false)
  })
}
