pragma ComponentBehavior: Bound

// A one-line text field in the popups' style, with a dim placeholder.
import QtQuick

Rectangle {
  id: box
  property alias text: input.text
  property string placeholder
  property bool password: false
  signal accepted()
  signal cancelled()

  function focusInput() {
    input.forceActiveFocus();
  }

  implicitWidth: 200
  implicitHeight: 36
  radius: Config.pillRadius
  // Lighter than the lifted row block it sits on.
  color: Config.field
  border.width: input.activeFocus ? 1 : 0
  border.color: Config.dim

  QueryInput {
    id: input
    anchors.fill: parent
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    verticalAlignment: TextInput.AlignVCenter
    font.pixelSize: Config.fontBody
    placeholder: box.placeholder
    echoMode: box.password ? TextInput.Password : TextInput.Normal
    onAccepted: box.accepted()
    Keys.onEscapePressed: box.cancelled()
  }
}
