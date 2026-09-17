import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "Keys.js" as Keys

// Typing indicator (wshowkeys-style): pill bottom-center showing
// pressed keys / chords ("A", "Ctrl + Shift + T"), fades after delay.
//
// Theme: 100% theme-driven — Color.popups background/text/border,
// Style.cornerRadius, Style.font. Re-themes live on `omarchy theme set`.
// Bar button opens popup with on/off switch; state persists inline
// in shell.json bar layout entry.
Panel {
  id: root
  moduleName: "syaifulmain.showkeys"
  ipcTarget: "syaifulmain.showkeys"
  manageIpc: false

  // ---- settings (inline shell.json entry, theme file is source of style)
  readonly property bool enabled: setting("enabled", true)
  // Chord width, capped at 20: clamped on read like hideDelayMs.
  readonly property int maxKeys: Math.max(1, Math.min(20, setting("maxKeys", 5)))
  // Clamped on read so hand-edited shell.json values (0, negative, huge)
  // can never break the timer or slider: single source of truth.
  readonly property int hideDelayMs: Math.max(100, Math.min(10000, setting("hideDelayMs", 1000)))
  // Pill size multiplier, slider-selected on curated stops like the
  // Display text-size row: slider works on stop index, calculated to scale.
  readonly property real pillScale: Math.max(0.5, Math.min(3, setting("scale", 1)))
  readonly property var scaleStops: [1, 1.5, 2, 2.5, 3]

  function nearestScaleStop(v) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < scaleStops.length; i++) {
      var d = Math.abs(scaleStops[i] - v)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  function currentScaleIndex() {
    return nearestScaleStop(pillScale)
  }

  function saveSettings(patch) {
    var entry = Object.assign({}, settings, patch)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function setEnabled(value) {
    saveSettings({ enabled: !!value })
  }

  // Seconds, for the popup slider (0.1 s steps). Stored as ms in shell.json.
  readonly property real hideDelaySec: hideDelayMs / 1000

  function setHideDelayMs(ms) {
    saveSettings({ hideDelayMs: Math.max(100, Math.min(10000, Math.round(ms))) })
  }

  function setMaxKeys(n) {
    saveSettings({ maxKeys: Math.max(1, Math.min(20, Math.round(n))) })
  }

  function setPillScale(s) {
    saveSettings({ scale: Math.max(0.5, Math.min(3, Number(s))) })
  }

  // Pill background: "default" (themed card), "transparent" (faint card),
  // or "none" (floating text, wshowkeys style). Unknown values fall back.
  readonly property string bgMode: {
    var m = setting("bgMode", "default")
    return m === "transparent" || m === "none" ? m : "default"
  }

  function setBgMode(m) {
    if (m !== "transparent" && m !== "none") m = "default"
    saveSettings({ bgMode: m })
  }

  // Pill border on/off. Independent from bgMode: bgMode "none"
  // already hides border, this toggle hides border on themed /
  // transparent backgrounds. Default true (old behavior).
  readonly property bool showBorder: setting("showBorder", true)

  function setShowBorder(v) {
    saveSettings({ showBorder: !!v })
  }

  // Pill vertical position, always horizontally centered.
  // Unknown values fall back to bottom.
  readonly property string position: {
    var p = setting("position", "bottom")
    return p === "top" || p === "center" ? p : "bottom"
  }

  function setPosition(p) {
    if (p !== "top" && p !== "center") p = "bottom"
    saveSettings({ position: p })
  }

  // Keys that never reach the pill (per-key exclusion).
  readonly property var excluded: setting("excluded", ({}))

  function isExcluded(code) {
    return excluded && excluded[code] === true
  }

  function setExcluded(code, v) {
    var next = Object.assign({}, excluded)
    if (v) next[code] = true
    else delete next[code]
    saveSettings({ excluded: next })
  }

  property int configTab: 0
  readonly property var configTabs: ["Display", "Keys"]

  // Custom display labels per evdev code, e.g. Down shown as an arrow.
  // Missing code = default label. Saving empty clears back to default.
  readonly property var keyLabels: setting("keyLabels", ({}))
  readonly property var keyList: Keys.allKeys()
  // Single merged row: name + rename input + show switch.
  readonly property real keyRowWidth: Style.space(140) + Style.space(110) + Style.space(56) + Style.space(8) * 2

  function keyLabel(code) {
    var v = keyLabels ? keyLabels[code] : ""
    return v === undefined || v === null ? "" : String(v)
  }

  function commitLabel(code, text) {
    // Truncate: unbounded rename string = pill overflow + shell.json bloat.
    // 12 chars fits pill, matches wshowkeys compact style.
    var t = String(text || "").replace(/^\s+|\s+$/g, "").slice(0, 12)
    if (t === keyLabel(code)) return
    var next = Object.assign({}, keyLabels)
    if (t === "") delete next[code]
    else next[code] = t
    saveSettings({ keyLabels: next })
  }

  // Live search over the key list (name or evdev code).
  property string keyQuery: ""
  readonly property var filteredKeys: {
    var q = keyQuery.replace(/^\s+|\s+$/g, "").toLowerCase()
    if (q === "") return keyList
    var out = []
    for (var i = 0; i < keyList.length; i++) {
      var k = keyList[i]
      if (k.label.toLowerCase().indexOf(q) !== -1 || String(k.code).indexOf(q) !== -1) out.push(k)
    }
    return out
  }

  // Single source for the keyboard glyph (bar button + popup hero).
  readonly property string keyGlyph: "󰌍"

  // ---- theme-driven appearance (no hardcoded colors)
  readonly property real fontSizePx: Style.fontPx(2.2) * pillScale
  readonly property int paddingPx: Math.max(Style.space(6), Math.round(fontSizePx * 0.45))
  readonly property int edgeMargin: Style.space(67)

  // ---- key state
  property var heldModifiers: ({})
  property var activeKeys: []
  property bool showing: false
  property string displayText: ""
  property bool configOpen: false
  property int repeatCount: 1
  property int lastCode: -1
  property string lastMods: ""
  property string grantStatus: ""

  function grantScriptPath() {
    return Qt.resolvedUrl("bin/showkeys-grant").toString().replace(/^file:\/\//, "")
  }

  function grantAccess() {
    if (grantProc.running) return
    root.grantStatus = "Waiting for password…"
    grantProc.command = ["pkexec", root.grantScriptPath()]
    grantProc.running = true
  }

  function composeText() {
    var parts = Keys.modifierLabels(heldModifiers, keyLabels)
    for (var i = 0; i < activeKeys.length; i++)
      parts.push(Keys.label(activeKeys[i], keyLabels))
    if (repeatCount > 1 && parts.length > 0)
      parts[parts.length - 1] = parts[parts.length - 1] + " " + repeatCount + "x"
    return parts.join(" + ")
  }

  function restartHide() {
    hideTimer.restart()
  }

  function refresh() {
    displayText = composeText()
    showing = displayText !== ""
    if (showing) restartHide()
  }

  function onKeyPressed(code) {
    if (!enabled) return
    // Defense in depth: backend filters, QML validates, Panel clamps.
    if (!isFinite(code) || Math.floor(code) !== code || code < 0 || code >= 0x100) return
    if (isExcluded(code)) return
    if (Keys.isModifier(code)) {
      // In-place mutate: no UI binds heldModifiers directly, only
      // composeText() reads it synchronously. Skips object alloc +
      // binding churn per press.
      heldModifiers[code] = true
    } else {
      var nk = []
      for (var k = 0; k < activeKeys.length; k++)
        if (activeKeys[k] !== code) nk.push(activeKeys[k])
      var modsKey = Object.keys(heldModifiers).sort().join(",")
      if (code === lastCode && modsKey === lastMods) repeatCount++
      else { repeatCount = 1; lastCode = code; lastMods = modsKey }
      nk.push(code)
      while (nk.length > maxKeys) nk.shift()
      activeKeys = nk
    }
    refresh()
  }

  // Releases only mutate the held sets — never the label. The pill keeps
  // showing the full chord until the hide delay fires after the last press,
  // so releasing Super + Ctrl + B shows the whole chord, not its decay
  // ("Super + Ctrl" → "Super" → gone). Modifier and key tracking are
  // independent: lifting a modifier must not wipe a still-held key.
  function onKeyReleased(code) {
    if (Keys.isModifier(code)) {
      delete heldModifiers[code]
    } else {
      var nk = []
      for (var k = 0; k < activeKeys.length; k++)
        if (activeKeys[k] !== code) nk.push(activeKeys[k])
      activeKeys = nk
    }
  }

  // Toggling off must wipe pill now, not wait hideTimer.
  // Old text lingered visible after disable = shoulder-surf leak.
  onEnabledChanged: {
    if (!root.enabled) {
      root.activeKeys = []
      root.heldModifiers = {}
      root.displayText = ""
      root.showing = false
      root.repeatCount = 1
      root.lastCode = -1
      root.lastMods = ""
    }
  }

  Timer {
    id: hideTimer
    interval: root.hideDelayMs
    onTriggered: {
      root.activeKeys = []
      root.heldModifiers = {}
      root.displayText = ""
      root.showing = false
      root.repeatCount = 1
      root.lastCode = -1
      root.lastMods = ""
    }
  }

  KeyMonitor {
    id: monitor
    onKeyPressed: function (code) { root.onKeyPressed(code) }
    onKeyReleased: function (code) { root.onKeyReleased(code) }
  }

  // One-shot privilege escalation: pkexec prompts for the password
  // graphically (Omarchy polkit agent), installs the udev rule, applies
  // the ACL. KeyMonitor rescans every 5 s and picks devices up alone.
  Process {
    id: grantProc
    onExited: function (exitCode) {
      if (exitCode === 0) root.grantStatus = "Access granted — rescanning keyboards…"
      else root.grantStatus = "Cancelled. Click the button to try again."
    }
  }

  // ---- IPC (single handler: Panel.manageIpc disabled so we own target)
  IpcHandler {
    target: "syaifulmain.showkeys"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function on(): string { root.setEnabled(true); return "on" }
    function off(): string { root.setEnabled(false); return "off" }
    function flip(): string { var next = !root.enabled; root.setEnabled(next); return next ? "on" : "off" }
    function state(): string {
      // Never expose displayText: old code returned live keystrokes
      // via IPC, any local process could snoop passwords.
      // showing bool is enough for scripting.
      return JSON.stringify({ enabled: root.enabled, maxKeys: root.maxKeys, hideDelayMs: root.hideDelayMs, scale: root.pillScale, bgMode: root.bgMode, showBorder: root.showBorder, position: root.position, showing: root.showing, devices: monitor.deviceCount, deviceAccess: monitor.deviceAccess })
    }
    function preview(text: string): string {
      // Truncate: unbounded IPC inject = pill overflow / spoof wall.
      root.displayText = String(text || "").replace(/^\s+|\s+$/g, "").slice(0, 64)
      root.showing = root.displayText !== ""
      if (root.showing) root.restartHide()
      return "ok"
    }
    function config(): string { root.openConfig(); return "ok" }
    function tab(index: string): string {
      var i = parseInt(index, 10)
      if (i >= 0 && i < root.configTabs.length) { root.openConfig(); root.configTab = i }
      return String(root.configTab)
    }
  }

  // ---- bar button
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.keyGlyph
    // Theme-colored icon always (bar.barForeground follows the theme).
    // Enabled state reads as full vs dimmed — never the urgent color.
    // `dimmed` (not manual opacity) keeps concealed logic + fade animation.
    dimmed: !root.enabled
    tooltipText: root.enabled ? "OmaShowKeys (on)" : "OmaShowKeys (off)"
    onPressed: function () { root.toggle() }
  }

  function openConfig() { root.close(); root.configOpen = true }
  function closeConfig() { root.configOpen = false }

  // ---- popup with on/off switch
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          title: "OmaShowKeys"
          meta: monitor.deviceAccess ? "WSHOWKEYS-STYLE KEYCAST" : "NO INPUT ACCESS"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          iconComponent: heroIcon
        }

        Component {
          id: heroIcon
          Text {
            textFormat: Text.PlainText
            text: root.keyGlyph
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        Toggle {
          width: parent.width
          label: "Show key presses"
          description: root.enabled ? "Pill visible at bottom center" : "Pill hidden"
          checked: root.enabled
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.setEnabled(!root.enabled)
        }

        // Display controls live in the Display tab of Key settings.

        Button {
          width: parent.width
          text: "Key settings…"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.openConfig()
        }

        Text {
          width: parent.width
          visible: !monitor.deviceAccess
          textFormat: Text.PlainText
          text: "Keyboard access needed to show key presses."
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Button {
          width: parent.width
          visible: !monitor.deviceAccess
          text: "Grant keyboard access"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.grantAccess()
        }

        Text {
          width: parent.width
          visible: !monitor.deviceAccess && root.grantStatus !== ""
          textFormat: Text.PlainText
          text: root.grantStatus
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }

  // ---- dedicated key-settings window (own view, not merged in popup)
  PanelWindow {
    id: configWindow
    visible: root.configOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "syaifulmain-showkeys-config"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // Click-away to close.
    MouseArea { anchors.fill: parent; onClicked: root.closeConfig() }

    BorderSurface {
      id: configCard
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.space(16)
      width: Math.min(parent.width - Style.space(48), root.keyRowWidth + contentLeftInset + contentRightInset + Style.space(14))
      height: Math.min(Style.space(560), parent.height - Style.space(48))

      Column {
        id: configColumn
        anchors.fill: parent
        anchors.leftMargin: configCard.contentLeftInset
        anchors.rightMargin: configCard.contentRightInset
        anchors.topMargin: configCard.contentTopInset
        anchors.bottomMargin: configCard.contentBottomInset
        spacing: Style.space(12)

        PanelHero {
          id: configHero
          title: "Key Settings"
          meta: "LABELS · DISPLAY · EXCLUDED"
          foreground: Color.popups.text
          fontFamily: Style.fontFamily
          iconComponent: heroIcon
        }

        Row {
          id: tabRow
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: root.configTabs

            Button {
              required property var modelData
              required property int index
              width: (tabRow.width - tabRow.spacing) / 2
              text: modelData
              foreground: Color.popups.text
              fontFamily: Style.fontFamily
              bordered: true
              active: root.configTab === index
              onClicked: root.configTab = index
            }
          }
        }

        TextField {
          id: searchRow
          visible: root.configTab !== 0
          width: parent.width
          foreground: Color.popups.text
          font.family: Style.fontFamily
          placeholderText: "Search name or code…"
          onTextChanged: root.keyQuery = text
        }

        // Virtualized: old ScrollView+Repeater built ~150 Row+TextField
        // at once on every config open. ListView recycles ~12 visible
        // delegates, reuseItems keeps pool across search filter changes.
        Item {
          width: parent.width
          height: parent.height - configHero.implicitHeight - tabRow.implicitHeight - (searchRow.visible ? searchRow.implicitHeight : 0) - closeBtn.implicitHeight - parent.spacing * 4

          Text {
            visible: root.configTab === 1 && root.filteredKeys.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: "No keys match."
            color: Color.popups.text
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }

          ListView {
            id: keyListView
            visible: root.configTab === 1 && root.filteredKeys.length > 0
            anchors.fill: parent
            clip: true
            model: root.filteredKeys
            spacing: Style.space(6)
            reuseItems: true
            cacheBuffer: 400
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Row {
              required property var modelData
              width: ListView.view.width - Style.space(14)
              spacing: Style.space(8)
              // Recycled delegate: refresh rename box on model swap.
              onModelDataChanged: field.text = root.keyLabel(modelData.code)

              Text {
                textFormat: Text.PlainText
                text: modelData.label + " · " + modelData.code
                color: Color.popups.text
                font.family: Style.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: Style.space(140)
                height: field.height
                verticalAlignment: Text.AlignVCenter
              }

              TextField {
                id: field
                width: Style.space(110)
                foreground: Color.popups.text
                font.family: Style.fontFamily
                placeholderText: modelData.label
                Component.onCompleted: field.text = root.keyLabel(modelData.code)
                onAccepted: root.commitLabel(modelData.code, field.text)
                onEditingFinished: root.commitLabel(modelData.code, field.text)
              }

              ToggleSwitch {
                checked: !(root.excluded && root.excluded[modelData.code] === true)
                foreground: Color.popups.text
                onToggled: root.setExcluded(modelData.code, !root.isExcluded(modelData.code))
              }
            }
          }

          // Display tab content is taller than its slot, so it scrolls.
          // Inlined (no Loader): Loader + availableWidth raced on tab
          // switch — Grid got 0-width first frame, radio buttons
          // left-clipped. Inline column tracks width continuously.
          ScrollView {
            id: displayScroll
            visible: root.configTab === 0
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
              width: displayScroll.availableWidth
              spacing: Style.space(12)

              Item {
                width: parent.width
                implicitHeight: Math.max(hideHeader.implicitHeight, hideValue.implicitHeight)

                PanelSectionHeader {
                  id: hideHeader
                  text: "HIDE AFTER"
                  foreground: Color.popups.text
                  fontFamily: Style.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: hideValue
                  textFormat: Text.PlainText
                  text: (hideSlider.dragging ? hideSlider.liveValue : root.hideDelaySec).toFixed(1) + "s"
                  color: Color.popups.text
                  font.family: Style.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                id: hideSlider
                bar: root.bar
                width: parent.width
                minimum: 0.1
                maximum: 10
                step: 0.1
                value: root.hideDelaySec
                onReleased: function (v) { root.setHideDelayMs(v * 1000) }
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(keysHeader.implicitHeight, keysValue.implicitHeight)

                PanelSectionHeader {
                  id: keysHeader
                  text: "MAX KEYS"
                  foreground: Color.popups.text
                  fontFamily: Style.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: keysValue
                  textFormat: Text.PlainText
                  text: String(keysSlider.dragging ? Math.round(keysSlider.liveValue) : root.maxKeys)
                  color: Color.popups.text
                  font.family: Style.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                id: keysSlider
                bar: root.bar
                width: parent.width
                minimum: 1
                maximum: 20
                step: 1
                integer: true
                value: root.maxKeys
                onReleased: function (v) { root.setMaxKeys(v) }
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(sizeHeader.implicitHeight, sizeValue.implicitHeight)

                PanelSectionHeader {
                  id: sizeHeader
                  text: "SIZE"
                  foreground: Color.popups.text
                  fontFamily: Style.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: sizeValue
                  textFormat: Text.PlainText
                  text: root.scaleStops[Math.round(sizeSlider.dragging ? sizeSlider.liveValue : root.currentScaleIndex())] + "x"
                  color: Color.popups.text
                  font.family: Style.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                id: sizeSlider
                bar: root.bar
                width: parent.width
                minimum: 0
                maximum: root.scaleStops.length - 1
                step: 1
                integer: true
                tickCount: root.scaleStops.length
                value: root.currentScaleIndex()
                onReleased: function (v) { root.setPillScale(root.scaleStops[Math.round(v)]) }
              }

              PanelSectionHeader {
                text: "BACKGROUND"
                foreground: Color.popups.text
                fontFamily: Style.fontFamily
              }

              Grid {
                width: parent.width
                columns: 3
                columnSpacing: Style.spacing.xs
                rowSpacing: Style.spacing.xs

                Repeater {
                  model: [
                    { key: "default", label: "Default" },
                    { key: "transparent", label: "Transparent" },
                    { key: "none", label: "None" },
                  ]

                  Button {
                    required property var modelData
                    text: modelData.label
                    fontSize: Style.font.caption
                    foreground: Color.popups.text
                    fontFamily: Style.fontFamily
                    horizontalPadding: Style.spacing.xs
                    verticalPadding: Style.spacing.controlPaddingY
                    bordered: true
                    width: Math.max(1, Math.floor((parent.width - Style.spacing.xs * 2) / 3))
                    active: root.bgMode === modelData.key
                    onClicked: root.setBgMode(modelData.key)
                  }
                }
              }

              PanelSectionHeader {
                text: "BORDER"
                foreground: Color.popups.text
                fontFamily: Style.fontFamily
              }

              Toggle {
                width: parent.width
                label: "Show border"
                description: root.showBorder ? "Pill border visible" : "Pill border hidden"
                checked: root.showBorder
                foreground: Color.popups.text
                fontFamily: Style.fontFamily
                onClicked: root.setShowBorder(!root.showBorder)
              }

              PanelSectionHeader {
                text: "POSITION"
                foreground: Color.popups.text
                fontFamily: Style.fontFamily
              }

              Grid {
                width: parent.width
                columns: 3
                columnSpacing: Style.spacing.xs
                rowSpacing: Style.spacing.xs

                Repeater {
                  model: [
                    { key: "top", label: "Top" },
                    { key: "center", label: "Center" },
                    { key: "bottom", label: "Bottom" },
                  ]

                  Button {
                    required property var modelData
                    text: modelData.label
                    fontSize: Style.font.caption
                    foreground: Color.popups.text
                    fontFamily: Style.fontFamily
                    horizontalPadding: Style.spacing.xs
                    verticalPadding: Style.spacing.controlPaddingY
                    bordered: true
                    width: Math.max(1, Math.floor((parent.width - Style.spacing.xs * 2) / 3))
                    active: root.position === modelData.key
                    onClicked: root.setPosition(modelData.key)
                  }
                }
              }
            }
          }
        }

        Button {
          id: closeBtn
          width: parent.width
          text: "Close"
          foreground: Color.popups.text
          fontFamily: Style.fontFamily
          onClicked: root.closeConfig()
        }
      }
    }
  }

  // NOTE: Display tab content lives inline in displayScroll above.
  // Do not re-add a Loader + Component split: it raced with
  // availableWidth on tab switch and clipped the radio buttons.

  // ---- pill overlay, one per screen, bottom center (wshowkeys position)
  component PillWindow: PanelWindow {
    id: pill
    visible: root.showing && root.enabled
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "syaifulmain-showkeys"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    BorderSurface {
      id: card
      radius: Style.cornerRadius
      color: root.bgMode === "none" ? "transparent"
        : root.bgMode === "transparent" ? Util.alpha(Color.popups.background, 0.45)
        : Util.alpha(Color.popups.background, 0.97)
      borderSpec: (root.bgMode === "none" || !root.showBorder) ? Border.none()
        : Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      width: contentText.implicitWidth + card.borderLeft + card.borderRight + root.paddingPx * 2 + Style.space(10)
      height: root.fontSizePx + card.borderTop + card.borderBottom + root.paddingPx * 2
      // Manual x/y: conditional vertical anchors briefly co-activate
      // on position change and stretch the pill full height.
      x: Math.round((parent.width - width) / 2)
      y: root.position === "top" ? root.edgeMargin
        : root.position === "center" ? Math.round((parent.height - height) / 2)
        : parent.height - height - root.edgeMargin

      Text {
        id: contentText
        anchors.centerIn: parent
        text: root.displayText
        textFormat: Text.PlainText
        font.family: Style.fontFamily
        font.pixelSize: root.fontSizePx
        color: Color.popups.text
      }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PillWindow {
        required property var modelData
        screen: modelData
      }
    }
  }
}
