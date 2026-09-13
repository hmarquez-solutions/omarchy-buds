import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Reads the daemon's status file and hands verbs to omarchy-buds. The panel
// never touches Bluetooth itself.
Item {
  id: root

  property var settings: ({})

  property bool daemonReachable: false
  property bool connected: false
  property string deviceName: ""
  property string modelName: ""
  property string family: ""
  property var leftBud: Model.defaultBud()
  property var rightBud: Model.defaultBud()
  property var caseBattery: ({ level: Model.LEVEL_UNKNOWN, charging: false })
  property string noiseMode: ""
  property var availableModes: []
  property int ambientVolume: 0
  property int ambientVolumeMax: 2
  property bool oneBudAnc: false
  property bool conversationDetect: false
  property bool touchLocked: false
  property string eqPreset: "off"
  property var eqPresets: ["off"]
  property bool finding: false
  property var supports: ({})
  property bool schemaUnsupported: false
  property string lastError: ""
  property string actionStatus: ""

  // Fixed interpreter and script path, never a PATH lookup: the CLI is what
  // carries a click to the daemon, so nothing in the session may redirect it.
  readonly property string interpreter: "/usr/bin/python3"
  readonly property string ctlPath: Quickshell.env("HOME") + "/.local/bin/omarchy-buds"
  readonly property bool busy: commandProcess.running
  // The daemon publishes here on change, so there is nothing to poll.
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/omarchy-buds/status.json"
  readonly property bool hasBuds: daemonReachable && connected
  readonly property bool hasBattery: hasBuds && (leftBud.level !== Model.LEVEL_UNKNOWN
    || rightBud.level !== Model.LEVEL_UNKNOWN || caseBattery.level !== Model.LEVEL_UNKNOWN)
  readonly property int maxStatusChars: 65536
  readonly property int commandTimeoutMs: 2500
  readonly property int maxCommandErrorChars: 512

  // How long an optimistic value is held before the daemon's own state wins.
  readonly property int settleHoldMs: 4000
  readonly property int actionStatusMs: 2600

  // Held over incoming reads until the daemon agrees, so a write already in flight
  // when the click landed cannot snap the control back.
  property string _pendingField: ""
  property var _pendingValue: null
  property string _commandErrorText: ""
  property bool _commandTimedOut: false

  // Single slot: a verb sent while another is in flight replaces the queued one
  // rather than being dropped, which is what arrow-key repeat produces.
  property var _queued: null

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function can(feature) {
    return supports && supports[feature] === true
  }

  // The CLI's whole environment. Only what it needs to find the daemon's
  // sockets and files; PATH is fixed and Python's own variables never arrive.
  function cliEnvironment() {
    var env = { PATH: "/usr/bin:/bin", LANG: "C.UTF-8" }
    var keep = ["HOME", "XDG_RUNTIME_DIR", "XDG_STATE_HOME"]
    for (var i = 0; i < keep.length; i++) {
      var value = Quickshell.env(keep[i])
      if (value) env[keep[i]] = String(value)
    }
    return env
  }

  function refresh() {
    stateFile.reload()
  }

  function applyLine(raw) {
    var text = String(raw)
    if (text.length > maxStatusChars) {
      daemonReachable = true
      connected = false
      schemaUnsupported = false
      lastError = "status file is too large"
      return
    }
    var status = Model.parseStatus(text)
    if (!status.ok) {
      // A line we cannot read still proves the daemon is running and writing.
      daemonReachable = true
      connected = false
      schemaUnsupported = status.schemaTooNew
      lastError = status.lastError
      return
    }
    daemonReachable = true
    schemaUnsupported = false
    lastError = ""
    applyStatus(status)
  }

  // The daemon removes the file when it stops, so an absent file is a stopped daemon.
  function stateGone() {
    daemonReachable = false
    connected = false
    schemaUnsupported = false
    lastError = ""
  }

  function applyStatus(status) {
    connected = status.connected
    deviceName = status.deviceName
    modelName = status.modelName
    family = status.family
    leftBud = status.left
    rightBud = status.right
    caseBattery = status.caseBattery
    availableModes = status.availableModes
    ambientVolumeMax = status.ambientVolumeMax
    eqPresets = status.eqPresets
    supports = status.supports

    noiseMode = _settle("noiseMode", status.noiseMode)
    ambientVolume = _settle("ambientVolume", status.ambientVolume)
    oneBudAnc = _settle("oneBudAnc", status.oneBudAnc)
    conversationDetect = _settle("conversationDetect", status.conversationDetect)
    touchLocked = _settle("touchLocked", status.touchLocked)
    eqPreset = _settle("eqPreset", status.eqPreset)
    finding = _settle("finding", status.finding)
  }

  function _settle(field, reported) {
    if (_pendingField !== field) return reported
    if (reported === _pendingValue) {
      _clearPending()
      return reported
    }
    return _pendingValue
  }

  function _clearPending() {
    _pendingField = ""
    _pendingValue = null
    settleTimer.stop()
  }

  function _appendCommandError(data) {
    var remaining = maxCommandErrorChars - _commandErrorText.length
    if (remaining > 0)
      _commandErrorText += String(data).slice(0, remaining)
  }

  function _send(argv, field, optimistic) {
    if (!argv || argv.length === 0) return
    if (commandProcess.running) {
      _queued = { argv: argv, field: field, optimistic: optimistic }
      _pendingField = field
      _pendingValue = optimistic
      root[field] = optimistic
      settleTimer.restart()
      return
    }
    _pendingField = field
    _pendingValue = optimistic
    _commandErrorText = ""
    _commandTimedOut = false
    root[field] = optimistic
    settleTimer.restart()
    commandProcess.command = [interpreter, "-I", ctlPath].concat(argv)
    commandTimeoutTimer.restart()
    commandProcess.running = true
  }

  // Guards the keyboard and the bar's right click too, not just the panel rows.
  function setNoiseMode(mode) {
    if (!hasBuds || availableModes.indexOf(mode) < 0) return
    _send(["noise", mode], "noiseMode", mode)
  }

  function cycleNoiseMode() {
    if (!hasBuds || availableModes.length === 0) return
    setNoiseMode(Model.nextIn(availableModes, noiseMode))
  }

  function setAmbientVolume(level) {
    if (!can("ambient_volume")) return
    var clamped = Math.max(0, Math.min(ambientVolumeMax, Math.round(level)))
    _send(["ambient-volume", String(clamped)], "ambientVolume", clamped)
  }

  function setConversationDetect(enabled) {
    if (!can("conversation_detect")) return
    _send(["conversation", enabled ? "on" : "off"], "conversationDetect", enabled)
  }

  function setOneBudAnc(enabled) {
    if (!can("one_bud_anc")) return
    _send(["onebud", enabled ? "on" : "off"], "oneBudAnc", enabled)
  }

  function setTouchLocked(locked) {
    if (!can("touch_lock")) return
    _send(["touch-lock", locked ? "on" : "off"], "touchLocked", locked)
  }

  function setEqPreset(preset) {
    if (!can("equalizer") || eqPresets.indexOf(preset) < 0) return
    _send(["eq", preset], "eqPreset", preset)
  }

  function cycleEqPreset() {
    setEqPreset(Model.nextIn(eqPresets, eqPreset))
  }

  function setFinding(active) {
    if (!can("find")) return
    _send(["find", active ? "start" : "stop"], "finding", active)
  }

  function toggleFinding() {
    setFinding(!finding)
  }

  Timer {
    // Bounds the optimistic hold, and re-reads because a verb that changed nothing
    // leaves the daemon's file untouched, so no watch fires to correct the display.
    id: settleTimer
    interval: root.settleHoldMs
    repeat: false
    onTriggered: { root._clearPending(); root.refresh() }
  }

  Timer {
    id: commandTimeoutTimer
    interval: root.commandTimeoutMs
    repeat: false
    onTriggered: {
      if (commandProcess.running) {
        root._commandTimedOut = true
        // SIGKILL makes this an end-to-end watchdog even if a helper ignores SIGTERM.
        commandProcess.signal(9)
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: root.actionStatusMs
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    // text() is stale inside the change signal, so both paths go through reload.
    onFileChanged: reload()
    onLoaded: root.applyLine(text())
    onLoadFailed: root.stateGone()
  }

  Process {
    id: commandProcess
    running: false
    command: []
    // Do not inherit the shell's environment: a PATH shadow or PYTHONPATH in the
    // session must not pick the interpreter or preload modules into the CLI.
    clearEnvironment: true
    environment: root.cliEnvironment()
    stderr: SplitParser {
      // Emit each OS read so Quickshell never accumulates an unbounded stderr buffer.
      splitMarker: ""
      onRead: function (data) { root._appendCommandError(data) }
    }
    onStarted: commandTimeoutTimer.restart()
    onExited: function (exitCode) {
      commandTimeoutTimer.stop()
      var timedOut = root._commandTimedOut
      root._commandTimedOut = false
      if (exitCode !== 0) {
        // Clearing the hold also stops the timer that would have re-read, so do it here.
        root._clearPending()
        root.refresh()
        root._queued = null
        // Its own field with its own timer, or the next status read wipes it unread.
        var text = timedOut ? "command timed out" : String(root._commandErrorText || "")
          .replace(/^omarchy-buds:\s*/, "")
        root.actionStatus = Model.elideError(text || "omarchy-buds rejected the command")
        actionStatusTimer.restart()
      }
      if (root._queued) {
        var next = root._queued
        root._queued = null
        root._send(next.argv, next.field, next.optimistic)
      }
    }
  }
}
