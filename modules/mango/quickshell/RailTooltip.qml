pragma ComponentBehavior: Bound

// A tooltip under a rail item, shown after half a second of hover
// (specs/014-quickshell-rail research R8). Set `hovered` from the item's
// HoverArea.
import QtQuick
import Quickshell

PopupWindow {
  id: tip
  required property Item target
  property string text
  // Dim text after `text`, e.g. the key that does the same.
  property string hint
  property bool hovered: false

  // Held as var: qmllint cannot see the anchor group's properties
  // (Quickshell's _Window types stub PopupAnchor), so they are set in JS.
  readonly property var anchorGroup: anchor
  Component.onCompleted: {
    anchorGroup.item = target;
    anchorGroup.edges = Edges.Bottom;
    anchorGroup.gravity = Edges.Bottom;
  }
  // 6 px of the window is the gap under the item.
  implicitWidth: label.implicitWidth + 24
  implicitHeight: label.implicitHeight + 16 + 6
  color: "transparent"
  property bool shown: false
  // Fades in and out; the window stays mapped until the fade-out ends.
  property real fade: hovered && shown && text !== "" ? 1 : 0
  Behavior on fade { Anim {} }
  visible: fade > 0
  onHoveredChanged: {
    shown = false;
    if (hovered) delay.restart(); else delay.stop();
  }

  Timer {
    id: delay
    interval: 500
    onTriggered: tip.shown = true
  }

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: 6
    radius: Config.pillRadius
    color: Config.island
    opacity: tip.fade

    Row {
      id: label
      anchors.centerIn: parent
      spacing: 8

      RailText {
        text: tip.text
        font.family: Config.railFont
        font.pixelSize: Config.fontSmall
      }

      RailText {
        visible: tip.hint !== ""
        text: tip.hint
        color: Config.dim
        font.family: Config.railFont
        font.pixelSize: Config.fontSmall
      }
    }
  }
}
