import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Backend: Hyprland's Lua key event bus. No daemon, no polling.
//
// While `active`, a one-line Lua handler registered through `hyprctl repl`
// re-emits every key event as a socket2 custom event
// (`custom>>omashowkeys,<xkb keycode>,<state>`). Quickshell receives it via
// Hyprland.rawEvent. Toggling off removes the handler, so the compositor
// does zero per-key work and no keystroke reaches this shell while off.
//
// Requires Omarchy Quattro: Hyprland >= 0.56 with the Lua config provider
// (the same provider Omarchy already uses for bindings.lua). Nothing is
// written to disk.
Item {
  id: monitor

  // Handler is registered only while active (keycast enabled).
  property bool active: true

  // True once `hyprctl repl` accepted a command; drives the popup notice.
  property bool available: false
  property string lastError: ""

  signal keyPressed(int code)
  signal keyReleased(int code)

  readonly property string eventName: "omashowkeys"

  // Note: not an expression — the handler body runs on the compositor
  // thread under a watchdog, so it stays one dispatch deep.
  readonly property string registerLua:
    'if OMASHOWKEYS_SUB then OMASHOWKEYS_SUB:remove() OMASHOWKEYS_SUB = nil end ' +
    'OMASHOWKEYS_SUB = hl.on("input.keyboard.key", function(kc, t, state) ' +
    'hl.dispatch(hl.dsp.event("omashowkeys," .. kc .. "," .. state .. "," .. t)) end)'
  readonly property string unregisterLua:
    'if OMASHOWKEYS_SUB then OMASHOWKEYS_SUB:remove() OMASHOWKEYS_SUB = nil end'

  // Serializes repl calls: a rapid toggle must not drop the last command.
  property string pendingLua: ""

  function validCode(c) {
    return isFinite(c) && Math.floor(c) === c && c >= 0 && c < 0x100
  }

  // `omashowkeys,<xkb keycode>,<state>,<timeMs>`; state 1 press, 0 release.
  // xkbcommon keycodes are evdev + 8, so the pill keeps working with the
  // evdev-based Keys.js map.
  function parse(data) {
    var parts = String(data == null ? "" : data).split(",")
    if (parts.length !== 4 || parts[0] !== monitor.eventName) return null
    var kc = Number(parts[1])
    if (!isFinite(kc) || Math.floor(kc) !== kc || kc <= 8 || kc >= 0x100 + 8) return null
    if (parts[2] !== "0" && parts[2] !== "1") return null
    var code = kc - 8
    if (!monitor.validCode(code)) return null
    var t = Number(parts[3])
    if (!isFinite(t) || t < 0) t = 0
    return { code: code, pressed: parts[2] === "1", timeMs: t }
  }

  // Hyprland can deliver the same key event twice (two listeners on the
  // keyboard signal), which the pill renders as a bogus "2x" repeat.
  // Drop only the immediate duplicate: same key + state, and either the
  // identical compositor timestamp or back-to-back arrival. A genuine
  // fast repeat has a different timestamp and is spaced by the repeat
  // rate, so it survives.
  property string lastSig: ""
  property real lastSigStamp: -1
  property real lastSigAt: 0

  function duplicateEvent(code, pressed, timeMs) {
    var sig = code + ":" + (pressed ? "1" : "0")
    var now = Date.now()
    var same = sig === monitor.lastSig
    var sameStamp = timeMs > 0 && timeMs === monitor.lastSigStamp
    var tooSoon = now - monitor.lastSigAt < 30
    monitor.lastSig = sig
    monitor.lastSigStamp = timeMs
    monitor.lastSigAt = now
    return same && (sameStamp || tooSoon)
  }

  function applyLua(lua) {
    if (repl.running) {
      monitor.pendingLua = lua
      return
    }
    monitor.lastError = ""
    repl.exitSeen = false
    repl.command = ["hyprctl", "repl", lua]
    repl.running = true
  }

  function sync() {
    if (monitor.active) monitor.applyLua(monitor.registerLua)
    else monitor.applyLua(monitor.unregisterLua)
  }

  Component.onCompleted: monitor.sync()
  onActiveChanged: monitor.sync()

  Process {
    id: repl
    // Distinguishes "failed to start" from a normal exit.
    property bool exitSeen: false
    command: ["hyprctl", "repl", "return 0"]

    stdout: SplitParser {
      onRead: function (line) {
        var text = String(line).trim()
        // Success replies "ok"; anything else is an eval error or a
        // "not in lua mode" refusal. hyprctl still exits 0, so the
        // reply text is the only reliable signal.
        if (text === "" || text === "ok") return
        monitor.available = false
        monitor.lastError = text.slice(0, 160)
      }
    }

    onRunningChanged: if (!running && !exitSeen) {
      monitor.available = false
      monitor.lastError = "hyprctl could not be started"
    }

    onExited: function (exitCode) {
      exitSeen = true
      if (exitCode !== 0) {
        monitor.available = false
        monitor.lastError = "hyprctl exited " + exitCode
      } else if (monitor.lastError === "") {
        monitor.available = true
      }
      if (monitor.pendingLua !== "") {
        var next = monitor.pendingLua
        monitor.pendingLua = ""
        monitor.applyLua(next)
      }
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (!event) return
      if (event.name === "configreloaded") {
        // The repl Lua VM is reinitialized on config reload, so the
        // subscription is gone. Re-register while active.
        if (monitor.active) monitor.applyLua(monitor.registerLua)
        return
      }
      if (event.name !== "custom") return
      var parsed = monitor.parse(event.data)
      if (parsed === null) return
      if (monitor.duplicateEvent(parsed.code, parsed.pressed, parsed.timeMs)) return
      if (parsed.pressed) monitor.keyPressed(parsed.code)
      else monitor.keyReleased(parsed.code)
    }
  }
}
