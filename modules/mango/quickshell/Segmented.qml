pragma ComponentBehavior: Bound

// A capsule of equal segments; the current one is accent-filled. With
// `glyph` set, every segment shows that icon, turned by its `options` entry
// in degrees.
import QtQuick
import QtQuick.Layouts

Rectangle {
  id: control
  property var options: []
  property int current: -1
  property string glyph: ""
  signal picked(int index)

  Layout.fillWidth: true
  implicitHeight: 40
  radius: height / 2
  color: Config.raised

  RowLayout {
    anchors.fill: parent
    anchors.margins: 3
    spacing: 0

    Repeater {
      model: control.options
      Rectangle {
        id: segment
        required property var modelData
        required property int index
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: height / 2
        color: segment.index === control.current ? Config.fg : "transparent"
        RailText {
          visible: !control.glyph
          anchors.centerIn: parent
          text: segment.modelData
          font.pixelSize: Config.fontSmall
          font.weight: segment.index === control.current ? Font.Bold : Font.DemiBold
          color: segment.index === control.current ? Config.onAccent : Config.fg
        }
        Glyph {
          visible: !!control.glyph
          anchors.centerIn: parent
          text: control.glyph
          rotation: control.glyph ? segment.modelData : 0
          color: segment.index === control.current ? Config.onAccent : Config.fg
        }
        HoverArea {
          anchors.fill: parent
          tint: segment.index === control.current ? Config.onAccent : Config.fg
          onClicked: control.picked(segment.index)
        }
      }
    }
  }
}
