import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// One window on the canvas: a live thumbnail placed in scene coordinates.
Item {
  id: tile

  property var win: ({})
  property var toplevel: null
  property bool capturing: false
  property bool live: true
  property bool hovered: false
  property bool dragging: false
  property bool selected: false
  property bool picked: false
  property bool focusedWindow: false
  property bool showLabel: false
  property real zoom: 1
  property real reveal: 1
  property color accent: Color.accent
  property color foreground: Color.foreground
  property color background: Color.background
  property string fontFamily: Style.font.family

  readonly property bool hasContent: view.hasContent
  readonly property var desktopEntry: {
    try { return DesktopEntries.heuristicLookup(win.appClass || "") } catch (e) { return null }
  }
  readonly property string iconSource: {
    var name = desktopEntry && desktopEntry.icon ? desktopEntry.icon : (win.appClass || "")
    try { return Quickshell.iconPath(name, true) || "" } catch (e) { return "" }
  }
  readonly property string appName: desktopEntry && desktopEntry.name ? desktopEntry.name : (win.appClass || "")

  function grab() {
    if (!tile.live && view.captureSource) view.captureFrame()
  }

  // Soft shadow so windows read as separate objects on the canvas.
  Rectangle {
    anchors.fill: parent
    anchors.margins: tile.dragging ? -10 : -4
    anchors.topMargin: tile.dragging ? -4 : -1
    anchors.bottomMargin: tile.dragging ? -18 : -7
    radius: face.radius + 8
    color: "black"
    opacity: (tile.dragging ? 0.45 : 0.25) * tile.reveal
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  Rectangle {
    id: face
    anchors.fill: parent
    // Fades with the overlay so the zoom from/to the real window has no
    // opaque letterbox or placeholder flash around it.
    color: tile.hasContent ? "transparent" : Util.alpha(tile.background, 0.92 * Math.min(1, tile.reveal * 1.5))
    radius: Math.max(0, Style.cornerRadius * tile.zoom)
    clip: true

    ScreencopyView {
      id: view
      anchors.fill: parent
      captureSource: tile.capturing && tile.toplevel ? tile.toplevel.wayland : null
      live: tile.capturing && tile.live
      paintCursor: false
      onCaptureSourceChanged: Qt.callLater(tile.grab)
    }

    Column {
      anchors.centerIn: parent
      spacing: Math.max(2, 8 * Math.min(1, tile.zoom * 2))
      visible: !tile.hasContent
      opacity: Math.min(1, tile.reveal * 1.5)
      Image {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(face.width, face.height) * 0.32
        height: width
        source: tile.iconSource
        sourceSize: Qt.size(128, 128)
        visible: source != ""
        smooth: true
        asynchronous: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: face.width * 0.9
        horizontalAlignment: Text.AlignHCenter
        text: tile.appName || "Window"
        color: Util.alpha(tile.foreground, 0.7)
        font.family: tile.fontFamily
        font.pixelSize: Math.max(8, Math.min(18, face.height * 0.08))
        elide: Text.ElideRight
        visible: face.height > 40
      }
    }

    // The reference lightens the window under the pointer.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(1, 1, 1, 1)
      opacity: tile.dragging ? 0.16 : tile.hovered ? 0.13 : 0
      Behavior on opacity { NumberAnimation { duration: 110 } }
    }

    Rectangle {
      anchors.fill: parent
      color: tile.accent
      opacity: tile.picked ? 0.14 : 0
      Behavior on opacity { NumberAnimation { duration: 110 } }
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -border.width
    color: "transparent"
    radius: face.radius + border.width
    opacity: tile.reveal
    border.width: tile.selected || tile.hovered || tile.picked ? 2 : 1
    border.color: tile.selected || tile.picked ? tile.accent
                  : tile.hovered ? Qt.rgba(1, 1, 1, 0.7)
                  : Util.alpha(tile.foreground, tile.focusedWindow ? 0.5 : 0.22)
    Behavior on border.color { ColorAnimation { duration: 110 } }
  }

  // Title pill above the tile (hover / selection / "always show titles").
  Rectangle {
    id: pill
    readonly property bool shown: tile.reveal > 0.5 && !tile.dragging && (tile.hovered || tile.selected || tile.showLabel)
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
    x: (tile.width - width) / 2
    y: -height - 8
    width: pillRow.implicitWidth + 16
    height: pillRow.implicitHeight + 8
    radius: Math.max(2, Style.cornerRadius)
    // Fades with the overlay so the zoom from/to the real window has no
    // opaque letterbox or placeholder flash around it.
    color: tile.hasContent ? "transparent" : Util.alpha(tile.background, 0.92 * Math.min(1, tile.reveal * 1.5))
    border.width: 1
    border.color: tile.selected ? tile.accent : Util.alpha(tile.foreground, 0.25)

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: 6
      Image {
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14
        source: tile.iconSource
        sourceSize: Qt.size(32, 32)
        visible: source != ""
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(120, Math.min(tile.width, 520)) - 70)
        text: tile.win.title || tile.appName
        color: tile.foreground
        font.family: tile.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: tile.win.special ? "scratchpad" : "ws " + (tile.win.workspaceName || "")
        color: Util.alpha(tile.foreground, 0.5)
        font.family: tile.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
