pragma ComponentBehavior: Bound

// A clickable area that tints itself while the pointer is over it. The tint
// follows the parent's corner radius; set `tint` to the parent's text colour
// on accent-filled controls so it shows against the fill.
import QtQuick

MouseArea {
  id: area
  property real radius: (parent as Rectangle)?.radius ?? Config.chipRadius
  property color tint: Config.fg

  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor

  Rectangle {
    anchors.fill: parent
    radius: area.radius
    color: area.tint
    // A dark tint on the light accent fill reads weaker, so it gets more.
    opacity: area.containsMouse ? (Qt.colorEqual(area.tint, Config.onAccent) ? 0.22 : 0.1) : 0
    Behavior on opacity { Anim {} }
  }
}
