import QtQuick
import Quickshell.Io

// Backend: runs KeyMonitor.py, emits keyPressed/keyReleased.
// Access comes from the one-click pkexec grant (udev rule + ACL).
Item {
  id: monitor

  // Pessimistic until the backend reports: DEV 0 (no access) must show
  // the grant button, so "unknown" and "none" both start as no-access.
  property bool deviceAccess: false
  property int deviceCount: 0

  signal keyPressed(int code)
  signal keyReleased(int code)

  // Backend crash-loop guard: 2s -> 30s backoff, no CPU spin if
  // python3 missing or script broken.
  property int restartDelayMs: 2000

  function validCode(c) {
    // Python already filters <0x100, but stdout is untrusted input.
    // Clamp here so compromised/future backend can't inject junk.
    return isFinite(c) && Math.floor(c) === c && c >= 0 && c < 0x100;
  }

  Process {
    id: process
    command: ["python3", monitorScriptPath()]
    running: true
    stdout: SplitParser {
      onRead: function (line) {
        var text = String(line).replace(/^\s+|\s+$/g, "")
        if (text.indexOf("P ") === 0 || text.indexOf("R ") === 0) {
          var code = parseInt(text.slice(2), 10)
          if (!monitor.validCode(code)) return
          if (text.charAt(0) === "P") monitor.keyPressed(code)
          else monitor.keyReleased(code)
        } else if (text.indexOf("DEV ") === 0) {
          var n = parseInt(text.slice(4), 10)
          // Clamp: backend bug can't set deviceCount to huge/NaN.
          if (!isFinite(n) || n < 0) n = 0
          n = Math.min(64, Math.floor(n))
          monitor.deviceCount = n
          monitor.deviceAccess = n > 0
          if (!monitor.deviceAccess)
            console.warn("omashowkeys: no readable /dev/input devices — use the Grant button in the popup")
        }
      }
    }
    onExited: {
      monitor.restartDelayMs = Math.min(30000, monitor.restartDelayMs * 2)
      restartTimer.interval = monitor.restartDelayMs
      restartTimer.restart()
    }
  }

  // Successful start resets backoff. SplitParser has no onFirstRead,
  // so reset when device count arrives (backend alive proof).
  onDeviceCountChanged: {
    monitor.restartDelayMs = 2000
    restartTimer.interval = 2000
  }

  function monitorScriptPath() {
    return Qt.resolvedUrl("KeyMonitor.py").toString().replace(/^file:\/\//, "")
  }

  Timer {
    id: restartTimer
    interval: 2000
    onTriggered: process.running = true
  }
}
