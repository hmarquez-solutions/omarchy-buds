// Runs Model.js outside the shell. Usage: node tests/model.test.js
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const assert = require("node:assert/strict")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const Model = {}
vm.runInContext(source + "\n" + exportsList(source), vm.createContext({ Model }))

// Every top-level `var` and `function` in Model.js becomes a property of Model.
function exportsList(src) {
  const names = new Set()
  for (const m of src.matchAll(/^(?:var|function)\s+([A-Za-z_]\w*)/gm)) names.add(m[1])
  return [...names].map((n) => `Model.${n} = ${n}`).join("\n")
}

const tests = []
const test = (name, fn) => tests.push([name, fn])
// Arrays built inside the vm context carry a different Array.prototype, which
// deepStrictEqual treats as a mismatch; compare by shape instead.
const same = (actual, expected) => assert.equal(JSON.stringify(actual), JSON.stringify(expected))

const sample = {
  schema_version: 1,
  connected: true,
  device: { name: "Hector's Buds4 Pro", model: "Galaxy Buds4 Pro", family: "buds3" },
  battery: {
    left: { level: 87, placement: "wearing", charging: false },
    right: { level: 91, placement: "case", charging: true },
    case: { level: 64, charging: false }
  },
  noise: { mode: "anc", available: ["off", "anc", "ambient", "adaptive"], ambient_volume: 1, ambient_volume_max: 2, one_bud_anc: true, conversation_detect: false },
  touch: { locked: false },
  equalizer: { preset: "soft", presets: ["off", "bass", "soft", "dynamic", "clear", "treble"] },
  find: { active: false },
  supports: { noise_control: true, touch_lock: true }
}

test("parses a full status", () => {
  const s = Model.parseStatus(JSON.stringify(sample))
  assert.equal(s.ok, true)
  assert.equal(s.connected, true)
  assert.equal(s.modelName, "Galaxy Buds4 Pro")
  assert.equal(s.left.level, 87)
  assert.equal(s.right.charging, true)
  assert.equal(s.caseBattery.level, 64)
  assert.equal(s.noiseMode, "anc")
  same(s.availableModes, ["off", "anc", "ambient", "adaptive"])
  assert.equal(s.eqPreset, "soft")
  assert.equal(Model.supports(s, "touch_lock"), true)
  assert.equal(Model.supports(s, "equalizer"), false)
})

test("empty and non-JSON files are errors, not throws", () => {
  assert.equal(Model.parseStatus("").ok, false)
  assert.equal(Model.parseStatus("   ").lastError, "Empty status file")
  assert.equal(Model.parseStatus("{nope").lastError, "Status file is not JSON")
  assert.equal(Model.parseStatus("[1,2]").ok, true) // arrays are objects; every field falls back
  assert.equal(Model.parseStatus("42").lastError, "Status file is not an object")
})

test("oversized status files are rejected before JSON parsing", () => {
  const s = Model.parseStatus("x".repeat(Model.MAX_STATUS_CHARS + 1))
  assert.equal(s.ok, false)
  assert.equal(s.lastError, "Status file is too large")
})

test("a newer schema is flagged rather than half-read", () => {
  const s = Model.parseStatus(JSON.stringify({ ...sample, schema_version: 99 }))
  assert.equal(s.ok, false)
  assert.equal(s.schemaTooNew, true)
})

test("missing sections fall back to defaults", () => {
  const s = Model.parseStatus(JSON.stringify({ schema_version: 1, connected: false }))
  assert.equal(s.ok, true)
  assert.equal(s.left.level, Model.LEVEL_UNKNOWN)
  assert.equal(s.noiseMode, "")
  same(s.availableModes, [])
  same(s.eqPresets, ["off"])
  assert.equal(Model.hasBattery(s), false)
})

test("null battery levels are unknown, and unknown placements are disconnected", () => {
  const s = Model.parseStatus(JSON.stringify({ schema_version: 1, battery: { left: { level: null, placement: "orbit" } } }))
  assert.equal(s.left.level, Model.LEVEL_UNKNOWN)
  assert.equal(s.left.placement, "disconnected")
  assert.equal(Model.levelText(s.left.level), "—")
  assert.equal(Model.levelFraction(s.left.level), 0)
})

test("unknown modes and presets are dropped", () => {
  const s = Model.parseStatus(JSON.stringify({ schema_version: 1, noise: { mode: "loud", available: ["off", "loud"] }, equalizer: { preset: "wub" } }))
  assert.equal(s.noiseMode, "")
  same(s.availableModes, ["off"])
  assert.equal(s.eqPreset, "off")
})

test("meta text prefers charging over placement", () => {
  assert.equal(Model.budMeta({ level: 50, charging: true, placement: "case" }), "Charging")
  assert.equal(Model.budMeta({ level: 50, charging: false, placement: "case" }), "In case")
  assert.equal(Model.caseMeta({ level: 64, charging: true }), "Charging")
  assert.equal(Model.caseMeta({ level: 64, charging: false }), "")
  assert.equal(Model.caseMeta({ level: Model.LEVEL_UNKNOWN, charging: false }), "Dock a bud to read")
  assert.equal(Model.budMeta({ level: 50, charging: false, placement: "wearing" }), "In ear")
  assert.equal(Model.budMeta({ level: 50, charging: false, placement: "disconnected" }), "")
})

test("nextIn cycles and copes with an unknown current value", () => {
  assert.equal(Model.nextIn(["off", "anc", "ambient"], "anc"), "ambient")
  assert.equal(Model.nextIn(["off", "anc", "ambient"], "ambient"), "off")
  assert.equal(Model.nextIn(["off", "anc"], ""), "off")
  assert.equal(Model.nextIn([], "anc"), "")
})

test("lowestLevel ignores unknown buds", () => {
  const s = Model.parseStatus(JSON.stringify(sample))
  assert.equal(Model.lowestLevel(s), 87)
  s.left.level = Model.LEVEL_UNKNOWN
  assert.equal(Model.lowestLevel(s), 91)
  s.right.level = Model.LEVEL_UNKNOWN
  assert.equal(Model.lowestLevel(s), Model.LEVEL_UNKNOWN)
})

test("short noise labels fit a chip", () => {
  assert.equal(Model.noiseModeShort("anc"), "ANC")
  assert.equal(Model.noiseModeShort("ambient"), "Ambient")
  assert.equal(Model.noiseModeShort("nope"), "Unknown")
  assert.equal(Model.eqShort("bass"), "Bass")
  assert.equal(Model.eqShort("treble"), "Treble")
  assert.equal(Model.eqShort("nope"), "Off")
})

test("chipOptions keeps the daemon's order and labels each value", () => {
  same(Model.chipOptions(["off", "anc"], Model.noiseModeShort), [{ value: "off", label: "Off" }, { value: "anc", label: "ANC" }])
  same(Model.chipOptions(null, Model.eqName), [])
})

test("anyBudLow ignores unknown and charging buds", () => {
  const low = { level: 15, charging: false, placement: "wearing" }
  const lowCharging = { level: 15, charging: true, placement: "case" }
  const fine = { level: 80, charging: false, placement: "wearing" }
  assert.equal(Model.anyBudLow(low, fine, 20), true)
  assert.equal(Model.anyBudLow(fine, low, 20), true)
  assert.equal(Model.anyBudLow(lowCharging, fine, 20), false)
  assert.equal(Model.anyBudLow(Model.defaultBud(), fine, 20), false)
  assert.equal(Model.anyBudLow({ level: 20, charging: false }, fine, 20), true)
})

test("indexOrFirst falls back to the first chip", () => {
  assert.equal(Model.indexOrFirst(["off", "anc", "ambient"], "ambient"), 2)
  assert.equal(Model.indexOrFirst(["off", "anc"], ""), 0)
  assert.equal(Model.indexOrFirst(null, "anc"), 0)
})

test("errors are elided to one row", () => {
  const long = "x".repeat(300)
  assert.equal(Model.elideError(long).length, Model.ELIDED_ERROR_CHARS + 1)
  assert.equal(Model.elideError("  a  b \n c "), "a b c")
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log(`ok   ${name}`)
  } catch (e) {
    failed++
    console.log(`FAIL ${name}\n     ${e.message}`)
  }
}
console.log(`\n${tests.length - failed}/${tests.length} passed`)
process.exit(failed ? 1 : 0)
