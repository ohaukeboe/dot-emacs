pragma ComponentBehavior: Bound

// A bare one-line text input with a dim placeholder, for search and filter
// fields. It draws no background: put it on a surface, or use TextBox.
import QtQuick

TextInput {
  id: input
  property string placeholder

  color: Config.fg
  selectionColor: Config.fg
  selectedTextColor: Config.onAccent
  font.family: Config.railFont
  font.pixelSize: Config.fontLabel
  clip: true

  RailText {
    visible: input.text === ""
    anchors.verticalCenter: parent.verticalCenter
    text: input.placeholder
    color: Config.dim
    font.pixelSize: input.font.pixelSize
  }
}
