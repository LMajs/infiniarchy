import QtQuick
import qs.Commons

// Bird's-eye view of the whole canvas. Click or drag to move the viewport.
Rectangle {
  id: map

  property var windows: []
  property var bounds: ({ x: 0, y: 0, w: 1, h: 1 })
  property var viewport: ({ x: 0, y: 0, w: 1, h: 1 })
  property string selectedAddr: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color background: Color.background

  signal jump(real worldX, real worldY)

  readonly property real pad: 8
  // Fixed to the content (not the viewport) so the map doesn't rescale while dragging.
  readonly property var world: {
    var b = bounds, mx = b.w * 0.08, my = b.h * 0.08
    return { x: b.x - mx, y: b.y - my, w: Math.max(1, b.w + mx * 2), h: Math.max(1, b.h + my * 2) }
  }
  readonly property real k: Math.min((width - pad * 2) / world.w, (height - pad * 2) / world.h)
  readonly property real ox: pad + ((width - pad * 2) - world.w * k) / 2 - world.x * k
  readonly property real oy: pad + ((height - pad * 2) - world.h * k) / 2 - world.y * k

  color: Util.alpha(background, 0.82)
  radius: Math.max(2, Style.cornerRadius)
  border.width: 1
  border.color: Util.alpha(foreground, 0.18)
  clip: true

  Repeater {
    model: map.windows
    Rectangle {
      required property var modelData
      x: map.ox + modelData.x * map.k
      y: map.oy + modelData.y * map.k
      width: Math.max(2, modelData.w * map.k)
      height: Math.max(2, modelData.h * map.k)
      color: modelData.address === map.selectedAddr ? Util.alpha(map.accent, 0.85) : Util.alpha(map.foreground, 0.3)
    }
  }

  Rectangle {
    x: map.ox + map.viewport.x * map.k
    y: map.oy + map.viewport.y * map.k
    width: map.viewport.w * map.k
    height: map.viewport.h * map.k
    color: Util.alpha(map.accent, 0.08)
    border.width: 1
    border.color: Util.alpha(map.accent, 0.9)
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    function go(mouse) { map.jump((mouse.x - map.ox) / map.k, (mouse.y - map.oy) / map.k) }
    onPressed: function(mouse) { go(mouse) }
    onPositionChanged: function(mouse) { if (pressed) go(mouse) }
  }
}
