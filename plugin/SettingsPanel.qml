import QtQuick
import qs.Commons
import qs.Ui
import "CanvasModel.js" as Model

// Settings card shown over the canvas: record a new toggle shortcut and tweak
// display options. Everything is persisted through the infiniarchy CLI so
// the config file and the Hyprland bind never drift apart.
BorderSurface {
  id: panel

  property var host: null
  property var cfg: ({})

  // "idle" | "recording" | "checking" | "captured" | "saving"
  property string phase: "idle"
  property string captured: ""
  property var conflicts: []
  property string message: ""
  property bool messageIsError: false
  property bool raltDown: false

  readonly property bool recording: phase === "recording"
  readonly property color fg: Color.menu.text
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.menuFamily

  signal closeRequested()

  width: Math.min(Style.space(560), parent ? parent.width - Style.space(40) : Style.space(560))
  height: Math.min(content.implicitHeight + Style.spacing.panelPadding * 2,
                  parent ? parent.height - Style.space(40) : content.implicitHeight + Style.spacing.panelPadding * 2)
  radius: Style.cornerRadius
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  function reset() {
    if (phase === "recording") host.stopRecording()
    phase = "idle"
    captured = ""
    conflicts = []
    message = ""
    raltDown = false
  }

  function startRecording() {
    message = ""
    captured = ""
    conflicts = []
    raltDown = false
    phase = "recording"
    host.startRecording()
    recordTimeout.restart()
  }

  function cancelRecording() {
    recordTimeout.stop()
    host.stopRecording()
    phase = "idle"
  }

  Timer {
    id: recordTimeout
    interval: 18000
    onTriggered: if (panel.phase === "recording") {
      panel.cancelRecording()
      panel.message = "Recording timed out."
      panel.messageIsError = true
    }
  }

  readonly property var scanNames: ({
    10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
    20: "MINUS", 21: "EQUAL", 34: "BRACKETLEFT", 35: "BRACKETRIGHT", 47: "SEMICOLON",
    48: "APOSTROPHE", 49: "GRAVE", 51: "BACKSLASH", 59: "COMMA", 60: "PERIOD", 61: "SLASH"
  })

  function keyName(event) {
    var k = event.key
    if (scanNames[event.nativeScanCode] !== undefined) return scanNames[event.nativeScanCode]
    if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k)
    if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k)
    if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1)
    var specials = {}
    specials[Qt.Key_Space] = "SPACE"; specials[Qt.Key_Return] = "RETURN"; specials[Qt.Key_Enter] = "RETURN"
    specials[Qt.Key_Tab] = "TAB"; specials[Qt.Key_Backtab] = "TAB"; specials[Qt.Key_Backspace] = "BACKSPACE"
    specials[Qt.Key_Delete] = "DELETE"; specials[Qt.Key_Insert] = "INSERT"; specials[Qt.Key_Home] = "HOME"
    specials[Qt.Key_End] = "END"; specials[Qt.Key_PageUp] = "PAGE_UP"; specials[Qt.Key_PageDown] = "PAGE_DOWN"
    specials[Qt.Key_Left] = "LEFT"; specials[Qt.Key_Right] = "RIGHT"; specials[Qt.Key_Up] = "UP"
    specials[Qt.Key_Down] = "DOWN"; specials[Qt.Key_Print] = "PRINT"; specials[Qt.Key_Pause] = "PAUSE"
    specials[Qt.Key_Menu] = "MENU"
    return specials[k] || ""
  }

  function isModifier(event) {
    var k = event.key
    return k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta ||
           k === Qt.Key_Super_L || k === Qt.Key_Super_R || k === Qt.Key_AltGr ||
           k === Qt.Key_Hyper_L || k === Qt.Key_Hyper_R || k === Qt.Key_CapsLock
  }

  // Called by Canvas.qml for every key while recording. Returns true if handled.
  function handleKeyPress(event) {
    if (!recording) return false
    if (event.nativeScanCode === 108 || event.key === Qt.Key_AltGr) raltDown = true
    if (isModifier(event)) return true
    var mods = event.modifiers
    if (event.key === Qt.Key_Escape && !(mods & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier))) {
      cancelRecording()
      return true
    }
    var name = keyName(event)
    if (!name) {
      message = "That key can't be used — try a letter, number or F-key."
      messageIsError = true
      return true
    }
    var parts = []
    if (mods & Qt.MetaModifier) parts.push("SUPER")
    if (mods & Qt.ControlModifier) parts.push("CTRL")
    if (mods & Qt.ShiftModifier) parts.push("SHIFT")
    if (raltDown) parts.push("RALT")
    else if (mods & Qt.AltModifier) parts.push("ALT")
    if (parts.length === 0) {
      message = "Add a modifier (Super, Ctrl, Alt, Right Alt or Shift) so the key still types normally."
      messageIsError = true
      return true
    }
    parts.push(name)
    recordTimeout.stop()
    host.stopRecording()
    checkCombo(parts.join(" + "))
    return true
  }

  // Keyboard control while the panel is shown (not recording). Returns true if handled.
  function handleNavKey(event) {
    var k = event.key
    if (phase === "idle" && (k === Qt.Key_R || k === Qt.Key_Return || k === Qt.Key_Enter)) {
      startRecording()
      return true
    }
    if (phase === "captured") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (captured !== cfg.hotkey) save(); return true }
      if (k === Qt.Key_Escape) { reset(); return true }
    }
    return false
  }

  function handleKeyRelease(event) {
    if (event.nativeScanCode === 108 || event.key === Qt.Key_AltGr) raltDown = false
    return recording
  }

  function checkCombo(combo) {
    phase = "checking"
    captured = combo
    message = ""
    host.runCli(["hotkey", "check", combo], function(res) {
      if (!res || !res.ok) {
        phase = "idle"
        message = res && res.error ? res.error : "Couldn't check that shortcut."
        messageIsError = true
        return
      }
      captured = res.hotkey
      conflicts = res.conflicts || []
      phase = "captured"
      if (captured === cfg.hotkey) {
        message = "That's already the canvas shortcut."
        messageIsError = false
      } else if (conflicts.length) {
        message = "Already used for “" + conflicts.join("”, “") + "”. Saving will take it over."
        messageIsError = true
      }
    })
  }

  function save() {
    if (!captured) return
    phase = "saving"
    var args = ["hotkey", "set", captured]
    if (conflicts.length) args.push("--replace")
    host.runCli(args, function(res) {
      if (res && res.ok) {
        phase = "idle"
        message = "Saved. " + Model.hotkeyLabel(res.hotkey) + " now toggles the canvas."
        messageIsError = false
        captured = ""
        conflicts = []
      } else {
        phase = "captured"
        message = res && res.error ? res.error : "Saving failed."
        messageIsError = true
      }
    })
  }

  function resetDefault() {
    phase = "saving"
    host.runCli(["hotkey", "reset", "--replace"], function(res) {
      phase = "idle"
      message = res && res.ok ? "Back to " + Model.hotkeyLabel(res.hotkey) + "." : (res && res.error ? res.error : "Reset failed.")
      messageIsError = !(res && res.ok)
    })
  }

  function setOption(key, value) {
    host.runCli(["config", "set", key, String(value)], function(res) {
      if (!res || !res.ok) {
        message = res && res.error ? res.error : "Couldn't save " + key + "."
        messageIsError = true
      }
    })
  }

  MouseArea { anchors.fill: parent }

  // Scrolls when the panel is taller than the screen.
  Flickable {
    id: scroller
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

  Column {
    id: content
    width: scroller.width
    spacing: Style.spacing.panelGap

    Row {
      width: parent.width
      Column {
        width: parent.width - closeBtn.width
        spacing: 2
        Text {
          text: "Infiniarchy"
          color: panel.fg
          font.family: panel.fontFamily
          font.pixelSize: Style.font.title
        }
        Text {
          text: "Infinite canvas window overview"
          color: Util.alpha(panel.fg, 0.55)
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Button {
        id: closeBtn
        text: "Done"
        bordered: true
        onClicked: panel.closeRequested()
      }
    }

    // ── Shortcut ───────────────────────────────────────────────────────
    Column {
      width: parent.width
      spacing: Style.spacing.rowGap

      Text {
        text: "TOGGLE SHORTCUT"
        color: Util.alpha(panel.fg, 0.5)
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap

        Rectangle {
          id: chip
          width: parent.width - buttons.width - parent.spacing
          height: Math.max(Style.spacing.controlHeight, chipText.implicitHeight + Style.spacing.controlPaddingY * 2)
          radius: Math.max(2, Style.cornerRadius)
          color: panel.recording ? Util.alpha(panel.accent, 0.12) : Util.alpha(panel.fg, 0.05)
          border.width: 1
          border.color: panel.recording || panel.phase === "captured" ? panel.accent : Util.alpha(panel.fg, 0.2)

          SequentialAnimation on opacity {
            running: panel.recording
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.55; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
          }

          Text {
            id: chipText
            anchors.verticalCenter: parent.verticalCenter
            x: Style.spacing.controlPaddingX
            width: parent.width - Style.spacing.controlPaddingX * 2
            elide: Text.ElideRight
            color: panel.fg
            font.family: panel.fontFamily
            font.pixelSize: Style.font.subtitle
            text: panel.recording ? "Press the new shortcut…  (Esc cancels)"
                : panel.phase === "checking" ? "Checking " + Model.hotkeyLabel(panel.captured) + "…"
                : panel.phase === "saving" ? "Saving…"
                : panel.captured ? Model.hotkeyLabel(panel.captured)
                : Model.hotkeyLabel(panel.cfg.hotkey || "RALT + Q")
          }
        }

        Row {
          id: buttons
          spacing: Style.spacing.controlGap
          Button {
            visible: panel.phase === "idle" || panel.phase === "recording"
            text: panel.recording ? "Cancel" : "Change"
            bordered: true
            onClicked: panel.recording ? panel.cancelRecording() : panel.startRecording()
          }
          Button {
            visible: panel.phase === "captured"
            text: panel.conflicts.length ? "Replace" : "Save"
            bordered: true
            selected: true
            enabled: panel.captured !== panel.cfg.hotkey
            onClicked: panel.save()
          }
          Button {
            visible: panel.phase === "captured"
            text: "Cancel"
            bordered: true
            onClicked: panel.reset()
          }
        }
      }

      Text {
        width: parent.width
        visible: text.length > 0
        wrapMode: Text.Wrap
        text: panel.message
        color: panel.messageIsError ? Color.urgent : Util.alpha(panel.fg, 0.8)
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.spacing.controlGap
        Button {
          text: "Use Right Alt + Q"
          visible: (panel.cfg.hotkey || "") !== "RALT + Q" && panel.phase === "idle"
          onClicked: panel.resetDefault()
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: Util.alpha(panel.fg, 0.5)
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        text: "R or Enter records · Enter saves · Esc cancels. Right Alt shortcuts only react to the right-hand Alt key — Left Alt + the same key still reaches your apps. From a terminal: infiniarchy hotkey set \"SUPER + O\""
      }
    }

    // ── Display ────────────────────────────────────────────────────────
    Column {
      width: parent.width
      spacing: Style.spacing.rowGap

      Text {
        text: "DISPLAY"
        color: Util.alpha(panel.fg, 0.5)
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Toggle {
        width: parent.width
        label: "Arrange the real desktop too"
        description: "Off (default): arranging only changes the canvas; clicking a window just focuses it. On: going to a spot makes that workspace match the canvas (windows float at their canvas positions and move over from other workspaces). Turning it off puts windows back."
        checked: panel.cfg.canvasDesktop === true
        onClicked: {
          var turnOn = !checked
          panel.setOption("canvasDesktop", turnOn)
          if (!turnOn) panel.host.runCli(["release"], function(res) {
            panel.message = res && res.ok ? "Desktop sync off; " + res.released + " window(s) back to normal tiling." : (res && res.error ? res.error : "Release failed.")
            panel.messageIsError = !(res && res.ok)
            panel.host.loadLayout()
            panel.host.refresh(false)
          })
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - releaseBtn.width - parent.spacing
          wrapMode: Text.Wrap
          text: "Put every window the canvas floated back into normal tiling."
          color: Util.alpha(panel.fg, 0.6)
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Button {
          id: releaseBtn
          text: "Release windows"
          bordered: true
          onClicked: panel.host.runCli(["release"], function(res) {
            panel.message = res && res.ok ? "Released " + res.released + " window(s) back to tiling." : (res && res.error ? res.error : "Release failed.")
            panel.messageIsError = !(res && res.ok)
            panel.host.loadLayout()
            panel.host.refresh(false)
          })
        }
      }

      Toggle {
        width: parent.width
        label: "Live thumbnails"
        description: "Stream window contents while the canvas is open. Off = one snapshot per open."
        checked: panel.cfg.liveThumbnails !== false
        onClicked: panel.setOption("liveThumbnails", !checked)
      }

      Toggle {
        width: parent.width
        label: "Attach windows into chains"
        description: "Drop a window right next to (or above/below) another and they link up (a thin line joins them); drag one and the whole chain follows. Right-click a window to unlink it; right-drag to select several and right-click one to cut the group loose from the rest."
        checked: panel.cfg.attachWindows !== false
        onClicked: panel.setOption("attachWindows", !checked)
      }

      Toggle {
        width: parent.width
        label: "Flat view when zoomed in"
        description: "Zoom in far enough and the curved overview lights up and snaps to a straight 1:1 view of the canvas; zoom out to go back."
        checked: panel.cfg.flatView !== false
        onClicked: panel.setOption("flatView", !checked)
      }

      Toggle {
        width: parent.width
        label: "Dot grid"
        description: "Show the dotted grid on the canvas background."
        checked: panel.cfg.showDots !== false
        onClicked: panel.setOption("showDots", !checked)
      }

      Toggle {
        width: parent.width
        label: "Hint bar"
        description: "Show the one-line control hints at the bottom of the canvas."
        checked: panel.cfg.showHints !== false
        onClicked: panel.setOption("showHints", !checked)
      }

      Toggle {
        width: parent.width
        label: "Minimap"
        description: "Overview of the whole canvas in the corner."
        checked: panel.cfg.showMinimap !== false
        onClicked: panel.setOption("showMinimap", !checked)
      }

      Toggle {
        width: parent.width
        label: "Always show window titles"
        description: "Otherwise titles appear on hover and selection."
        checked: panel.cfg.showLabels === true
        onClicked: panel.setOption("showLabels", !checked)
      }

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - lensRow.width - parent.spacing
          text: "Lens curvature"
          color: panel.fg
          font.family: panel.fontFamily
          font.pixelSize: Style.font.subtitle
        }
        Row {
          id: lensRow
          spacing: Style.spacing.xs
          Repeater {
            model: [{ label: "Off", value: 0 }, { label: "Subtle", value: 0.3 }, { label: "Classic", value: 0.55 }, { label: "Strong", value: 0.85 }]
            Button {
              required property var modelData
              text: modelData.label
              bordered: true
              selected: Math.abs(Number(panel.cfg.lens === undefined ? 0.55 : panel.cfg.lens) - modelData.value) < 0.05
              onClicked: panel.setOption("lens", modelData.value)
            }
          }
        }
      }
    }

    // ── How to navigate ────────────────────────────────────────────────
    Column {
      width: parent.width
      spacing: Style.spacing.rowGap

      Text {
        text: "HOW TO NAVIGATE"
        color: Util.alpha(panel.fg, 0.5)
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Repeater {
        model: [
          { head: "Mouse" },
          { key: "Left-click window", text: "Go to it (activates the window and closes the canvas)" },
          { key: "Left-drag window", text: "Move it, together with its chain and any selected windows. Drop it right next to, above or below another window to link them" },
          { key: "Left-drag background", text: "Pan (also middle-drag, two-finger scroll, or WASD)" },
          { key: "Scroll", text: "Zoom around the pointer. Keep zooming in and it lights up into the flat 1:1 view; scroll out to return to the curved overview" },
          { key: "Right-drag", text: "Box-select windows" },
          { key: "Right-click window", text: "Unlink it from everything. On a selected window: keep the selection linked together, cut it loose from the rest" },
          { key: "Right-click background", text: "Clear the selection" },
          { key: "Middle-click window", text: "Close the window" },
          { key: "Double-click background", text: "Fit everything (also the grid button, 0 or F)" },
          { key: "Minimap", text: "Click or drag to jump around" },
          { head: "Keyboard" },
          { key: Model.hotkeyLabel(panel.cfg.hotkey || "RALT + Q"), text: "Open / close the canvas" },
          { key: "W A S D", text: "Pan (hold to keep moving)" },
          { key: "Q / E", text: "Jump to the previous / next window and centre it" },
          { key: "Arrows / H J K L", text: "Select the neighbouring window" },
          { key: "Enter / Space", text: "Go to the selected window" },
          { key: "Shift + arrows", text: "Move the selected window (and its chain)" },
          { key: "U", text: "Unlink the selected window" },
          { key: "Tab / Shift + Tab", text: "Cycle through windows" },
          { key: "+ / −", text: "Zoom in / out" },
          { key: "0 / F", text: "Fit everything" },
          { key: "Esc", text: "Clear the selection, then close" },
          { key: "Ctrl + ,", text: "This panel" }
        ]
        Item {
          required property var modelData
          width: parent.width
          height: modelData.head ? headText.implicitHeight + Style.space(4) : Math.max(keyText.implicitHeight, descText.implicitHeight)
          Text {
            id: headText
            visible: !!modelData.head
            anchors.bottom: parent.bottom
            text: modelData.head || ""
            color: panel.fg
            font.family: panel.fontFamily
            font.pixelSize: Style.font.subtitle
          }
          Text {
            id: keyText
            visible: !modelData.head
            width: Math.round(parent.width * 0.34)
            text: modelData.key || ""
            color: panel.accent
            wrapMode: Text.Wrap
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            id: descText
            visible: !modelData.head
            x: keyText.width + Style.space(10)
            width: parent.width - x
            text: modelData.text || ""
            color: Util.alpha(panel.fg, 0.75)
            wrapMode: Text.Wrap
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
  }
}
