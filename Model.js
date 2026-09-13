// No QML imports on purpose, so every function here runs in a plain JS harness.

// Highest schema_version this panel knows how to read.
var SUPPORTED_SCHEMA = 1

// A battery level the daemon has not reported.
var LEVEL_UNKNOWN = -1

// nf-md-check U+F012C; the Nerd Font ships this one, unlike its earbud glyphs.
var GLYPH_CHECK = "󰄬"

var NOISE_LABELS = {
  off: "Off",
  anc: "Noise Cancelling",
  ambient: "Ambient Sound",
  adaptive: "Adaptive"
}

// Short enough for a chip and the hero pill.
var NOISE_SHORT = {
  off: "Off",
  anc: "ANC",
  ambient: "Ambient",
  adaptive: "Adaptive"
}

var NOISE_KEYS = { o: "off", n: "anc", a: "ambient", d: "adaptive" }

var EQ_LABELS = {
  off: "Off",
  bass: "Bass Boost",
  soft: "Soft",
  dynamic: "Dynamic",
  clear: "Clear",
  treble: "Treble Boost"
}

// Chip labels; the long names above stay for the cycle key's status text.
var EQ_SHORT = {
  off: "Off",
  bass: "Bass",
  soft: "Soft",
  dynamic: "Dynamic",
  clear: "Clear",
  treble: "Treble"
}

var PLACEMENT_LABELS = {
  wearing: "In ear",
  idle: "Out",
  case: "In case",
  case_closed: "In case",
  disconnected: ""
}

// Longest error the panel will show inside a row, and the cut that leaves room for the ellipsis.
var MAX_ERROR_CHARS = 140
var ELIDED_ERROR_CHARS = 137
var MAX_STATUS_CHARS = 65536

function defaultBud() {
  return { level: LEVEL_UNKNOWN, charging: false, placement: "disconnected" }
}

// Full shape on every path, so the panel never reads undefined off a parse failure.
function defaultStatus() {
  return {
    ok: false,
    lastError: "",
    schemaVersion: 0,
    schemaTooNew: false,
    connected: false,
    deviceName: "",
    modelName: "",
    family: "",
    left: defaultBud(),
    right: defaultBud(),
    caseBattery: { level: LEVEL_UNKNOWN, charging: false },
    noiseMode: "",
    availableModes: [],
    ambientVolume: 0,
    ambientVolumeMax: 2,
    oneBudAnc: false,
    conversationDetect: false,
    touchLocked: false,
    eqPreset: "off",
    eqPresets: ["off"],
    finding: false,
    supports: {}
  }
}

function intOr(value, fallback) {
  var n = parseInt(value, 10)
  return isFinite(n) ? n : fallback
}

function boolOr(value, fallback) {
  return value === undefined || value === null ? fallback : value === true
}

function budFrom(raw) {
  var bud = defaultBud()
  if (!raw || typeof raw !== "object") return bud
  var level = raw.level === null || raw.level === undefined ? LEVEL_UNKNOWN : intOr(raw.level, LEVEL_UNKNOWN)
  bud.level = level < 0 || level > 100 ? LEVEL_UNKNOWN : level
  bud.charging = boolOr(raw.charging, false)
  bud.placement = typeof raw.placement === "string" && PLACEMENT_LABELS[raw.placement] !== undefined
    ? raw.placement : "disconnected"
  return bud
}

function caseFrom(raw) {
  var c = { level: LEVEL_UNKNOWN, charging: false }
  if (!raw || typeof raw !== "object") return c
  var level = raw.level === null || raw.level === undefined ? LEVEL_UNKNOWN : intOr(raw.level, LEVEL_UNKNOWN)
  c.level = level < 0 || level > 100 ? LEVEL_UNKNOWN : level
  c.charging = boolOr(raw.charging, false)
  return c
}

function stringList(raw, allowed) {
  var out = []
  if (!Array.isArray(raw)) return out
  for (var i = 0; i < raw.length; i++) {
    if (typeof raw[i] === "string" && (!allowed || allowed[raw[i]] !== undefined)) out.push(raw[i])
  }
  return out
}

// Parses one status.json as written by the daemon. Never throws.
function parseStatus(raw) {
  var status = defaultStatus()
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text.length > MAX_STATUS_CHARS) {
    status.lastError = "Status file is too large"
    return status
  }
  if (text === "") {
    status.lastError = "Empty status file"
    return status
  }

  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    status.lastError = "Status file is not JSON"
    return status
  }
  if (!data || typeof data !== "object") {
    status.lastError = "Status file is not an object"
    return status
  }

  status.schemaVersion = intOr(data.schema_version, 0)
  if (status.schemaVersion > SUPPORTED_SCHEMA) {
    status.schemaTooNew = true
    status.lastError = "Status schema " + status.schemaVersion + " is newer than this panel"
    return status
  }

  var device = data.device || {}
  var battery = data.battery || {}
  var noise = data.noise || {}
  var touch = data.touch || {}
  var eq = data.equalizer || {}
  var find = data.find || {}

  status.ok = true
  status.connected = boolOr(data.connected, false)
  status.deviceName = typeof device.name === "string" ? device.name : ""
  status.modelName = typeof device.model === "string" ? device.model : ""
  status.family = typeof device.family === "string" ? device.family : ""
  status.left = budFrom(battery.left)
  status.right = budFrom(battery.right)
  status.caseBattery = caseFrom(battery["case"])
  status.noiseMode = typeof noise.mode === "string" && NOISE_LABELS[noise.mode] !== undefined ? noise.mode : ""
  status.availableModes = stringList(noise.available, NOISE_LABELS)
  status.ambientVolume = Math.max(0, intOr(noise.ambient_volume, 0))
  status.ambientVolumeMax = Math.max(1, intOr(noise.ambient_volume_max, 2))
  status.oneBudAnc = boolOr(noise.one_bud_anc, false)
  status.conversationDetect = boolOr(noise.conversation_detect, false)
  status.touchLocked = boolOr(touch.locked, false)
  status.eqPreset = typeof eq.preset === "string" && EQ_LABELS[eq.preset] !== undefined ? eq.preset : "off"
  status.eqPresets = stringList(eq.presets, EQ_LABELS)
  if (status.eqPresets.length === 0) status.eqPresets = ["off"]
  status.finding = boolOr(find.active, false)
  status.supports = data.supports && typeof data.supports === "object" ? data.supports : {}
  return status
}

function supports(status, feature) {
  return !!(status && status.supports && status.supports[feature] === true)
}

function hasBattery(status) {
  return status.left.level !== LEVEL_UNKNOWN
    || status.right.level !== LEVEL_UNKNOWN
    || status.caseBattery.level !== LEVEL_UNKNOWN
}

function levelText(level) {
  return level === LEVEL_UNKNOWN ? "—" : level + "%"
}

function levelFraction(level) {
  return level === LEVEL_UNKNOWN ? 0 : Math.max(0, Math.min(1, level / 100))
}

// "Charging" beats placement: a bud in the case that is topping up says so.
function budMeta(bud) {
  if (!bud) return ""
  if (bud.charging) return "Charging"
  return PLACEMENT_LABELS[bud.placement] || ""
}

// The buds only read the case while one of them is docked in it.
function caseMeta(c) {
  if (!c || c.level === LEVEL_UNKNOWN) return "Dock a bud to read"
  return c.charging ? "Charging" : ""
}

function noiseModeName(mode) {
  return NOISE_LABELS[mode] || "Unknown"
}

function noiseModeShort(mode) {
  return NOISE_SHORT[mode] || "Unknown"
}

function eqName(preset) {
  return EQ_LABELS[preset] || "Off"
}

function eqShort(preset) {
  return EQ_SHORT[preset] || "Off"
}

// Values with their labels, in the order the daemon listed them, for a chip row.
function chipOptions(values, labeler) {
  var out = []
  if (!values) return out
  for (var i = 0; i < values.length; i++) out.push({ value: values[i], label: labeler(values[i]) })
  return out
}

// True when a bud that is reporting sits at or under the threshold and is not on charge.
function anyBudLow(left, right, threshold) {
  var buds = [left, right]
  for (var i = 0; i < buds.length; i++) {
    var b = buds[i]
    if (b && b.level !== LEVEL_UNKNOWN && b.level <= threshold && !b.charging) return true
  }
  return false
}

// Position of `current` in `list`, or 0 so a cursor always lands on a real chip.
function indexOrFirst(list, current) {
  if (!list) return 0
  var at = list.indexOf(current)
  return at < 0 ? 0 : at
}

function nextIn(list, current) {
  if (!list || list.length === 0) return ""
  var at = list.indexOf(current)
  return list[(at + 1) % list.length]
}

// The lowest level across whatever is reporting, for the bar to colour on.
function lowestLevel(status) {
  var levels = [status.left.level, status.right.level].filter(function (l) { return l !== LEVEL_UNKNOWN })
  if (levels.length === 0) return LEVEL_UNKNOWN
  return Math.min.apply(null, levels)
}

function elideError(text) {
  var s = String(text || "").replace(/\s+/g, " ").trim()
  if (s.length <= MAX_ERROR_CHARS) return s
  return s.substring(0, ELIDED_ERROR_CHARS) + "…"
}
