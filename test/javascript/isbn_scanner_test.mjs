import { test } from "node:test"
import assert from "node:assert/strict"
import { setImmediate } from "node:timers/promises"
import { build } from "esbuild"

const bundle = await build({
  entryPoints: ["app/javascript/controllers/isbn_scanner_controller.ts"],
  bundle: true,
  write: false,
  platform: "node",
  format: "esm",
  plugins: [{
    name: "camera-test-double",
    setup(build) {
      build.onResolve({ filter: /^html5-qrcode$/ }, () => ({ path: "camera", namespace: "camera-test" }))
      build.onLoad({ filter: /.*/, namespace: "camera-test" }, () => ({
        contents: `export class Html5Qrcode {
          constructor() { return globalThis.createTestScanner() }
        }
        export const Html5QrcodeSupportedFormats = { EAN_13: 13 };`
      }))
    }
  }]
})
const { default: ScannerController } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`
)

function deferred() {
  let resolve
  let reject
  const promise = new Promise((done, fail) => {
    resolve = done
    reject = fail
  })
  return { promise, resolve, reject }
}

function scanner() {
  const startup = deferred()
  const shutdown = deferred()
  let decoded
  let stops = 0
  const camera = {
    isScanning: false,
    start(camera, options, onDecoded) {
      decoded = onDecoded
      return startup.promise.then(() => { this.isScanning = true })
    },
    stop() {
      stops += 1
      return shutdown.promise.then(() => { this.isScanning = false })
    }
  }
  return { camera, startup, shutdown, decode: value => decoded(value), stops: () => stops }
}

function mount(t, cameras) {
  const originalFactory = globalThis.createTestScanner
  let created = 0
  let submissions = 0
  globalThis.createTestScanner = () => cameras[created++].camera
  const element = { isConnected: true }
  const controller = new ScannerController({ scope: { element } })
  const input = { value: "", closest: () => ({ requestSubmit() { submissions += 1 } }) }
  const status = { textContent: "" }
  Object.assign(controller, { viewportTarget: { id: "test-camera" }, inputTarget: input, statusTarget: status })
  t.after(async () => {
    element.isConnected = false
    controller.disconnect()
    await setImmediate()
    if (originalFactory === undefined) delete globalThis.createTestScanner
    else globalThis.createTestScanner = originalFactory
  })
  controller.connect()
  return { controller, element, input, status, created: () => created, submissions: () => submissions }
}

test("disconnect waits for pending startup and stops that scanner once", async t => {
  const camera = scanner()
  const page = mount(t, [camera])
  await setImmediate()
  page.element.isConnected = false
  page.controller.disconnect()
  page.controller.disconnect()
  assert.equal(camera.stops(), 0)
  camera.startup.resolve()
  await setImmediate()
  assert.equal(camera.stops(), 1)
  camera.shutdown.resolve()
  await setImmediate()
  assert.equal(camera.camera.isScanning, false)
})

test("reconnection waits for old cleanup before starting a new camera", async t => {
  const oldCamera = scanner()
  const newCamera = scanner()
  const page = mount(t, [oldCamera, newCamera])
  await setImmediate()
  page.controller.disconnect()
  page.controller.connect()
  oldCamera.startup.resolve()
  await setImmediate()
  assert.equal(page.created(), 1)
  assert.equal(oldCamera.stops(), 1)
  oldCamera.decode("old-isbn")
  assert.equal(page.input.value, "")
  oldCamera.shutdown.resolve()
  await setImmediate()
  assert.equal(page.created(), 2)
  newCamera.startup.resolve()
  await setImmediate()
  assert.equal(newCamera.stops(), 0)
  page.controller.disconnect()
  await setImmediate()
  assert.equal(newCamera.stops(), 1)
  newCamera.shutdown.resolve()
})

test("decoding stops the camera before submitting and ignores duplicate results", async t => {
  const camera = scanner()
  const page = mount(t, [camera])
  camera.startup.resolve()
  await setImmediate()
  camera.decode("9780134757599")
  camera.decode("duplicate")
  await setImmediate()
  assert.equal(page.input.value, "9780134757599")
  assert.equal(camera.stops(), 1)
  assert.equal(page.submissions(), 0)
  camera.shutdown.resolve()
  await setImmediate()
  assert.equal(page.submissions(), 1)
  page.controller.disconnect()
  await setImmediate()
  assert.equal(camera.stops(), 1)
})

test("leaving while a decoded result is stopping never submits the detached form", async t => {
  const camera = scanner()
  const page = mount(t, [camera])
  camera.startup.resolve()
  await setImmediate()
  camera.decode("9780134757599")
  page.element.isConnected = false
  page.controller.disconnect()
  camera.shutdown.resolve()
  await setImmediate()
  assert.equal(camera.stops(), 1)
  assert.equal(page.submissions(), 0)
})

test("startup failure reports the error and retains manual ISBN entry", async t => {
  const camera = scanner()
  const report = t.mock.method(console, "error", () => {})
  const page = mount(t, [camera])
  const error = new Error("Camera denied")
  camera.startup.reject(error)
  await setImmediate()
  assert.match(page.status.textContent, /enter the ISBN manually/)
  assert.deepEqual(report.mock.calls[0].arguments, ["Failed to start ISBN scanner", error])
  page.controller.disconnect()
  await setImmediate()
  assert.equal(camera.stops(), 0)
})

test("late startup failure cannot overwrite a reconnected scanner's status", async t => {
  const oldCamera = scanner()
  const newCamera = scanner()
  t.mock.method(console, "error", () => {})
  const page = mount(t, [oldCamera, newCamera])
  await setImmediate()
  page.controller.disconnect()
  page.controller.connect()
  oldCamera.startup.reject(new Error("Old camera denied"))
  await setImmediate()
  assert.equal(page.status.textContent, "")
  assert.equal(page.created(), 2)
  newCamera.startup.resolve()
  await setImmediate()
  page.controller.disconnect()
  newCamera.shutdown.resolve()
})

test("disconnect handles camera cleanup rejection", async t => {
  const camera = scanner()
  const report = t.mock.method(console, "error", () => {})
  const page = mount(t, [camera])
  camera.startup.resolve()
  await setImmediate()
  page.controller.disconnect()
  const error = new Error("Stop failed")
  camera.shutdown.reject(error)
  await setImmediate()
  assert.deepEqual(report.mock.calls[0].arguments, ["Failed to stop ISBN scanner", error])
})

test("decode cleanup failure is reported and does not submit the form", async t => {
  const camera = scanner()
  const report = t.mock.method(console, "error", () => {})
  const page = mount(t, [camera])
  camera.startup.resolve()
  await setImmediate()
  camera.decode("9780134757599")
  const error = new Error("Stop failed")
  camera.shutdown.reject(error)
  await setImmediate()
  assert.equal(page.submissions(), 0)
  assert.match(page.status.textContent, /Camera could not stop/)
  assert.deepEqual(report.mock.calls[0].arguments, ["Failed to process scanned ISBN", error])
})
