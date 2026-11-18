pragma ComponentBehavior: Bound

// The lock screen's and the greeter's card: an icon, a title over a status
// line, a password field and a key hint. Children go between the field and
// the hint (the greeter's session switch).
import QtQuick
import QtQuick.Layouts

FloatingCard {
  id: root
  property string icon
  property string title
  property string status
  property string hint
  property alias text: field.text
  default property alias content: extra.data
  signal accepted(string text)

  function clear() {
    field.text = "";
  }
  function focusInput() {
    field.focusInput();
  }

  implicitHeight: card.implicitHeight + 24

  ColumnLayout {
    id: card
    anchors.fill: parent
    anchors.margins: 12
    spacing: 10

    RowLayout {
      spacing: 10

      IconButton {
        icon: root.icon
        on: true
        onClicked: field.focusInput()
      }
      ColumnLayout {
        spacing: 2
        Title { text: root.title }
        Detail { text: root.status }
      }
    }

    TextBox {
      id: field
      Layout.fillWidth: true
      Layout.preferredHeight: 44
      // One step up from the island, as rows on it are; field is for a
      // raised card and glares here.
      color: Config.raised
      password: true
      placeholder: "Password"
      Component.onCompleted: focusInput()
      onAccepted: root.accepted(text)
      onCancelled: text = ""
    }

    ColumnLayout {
      id: extra
      Layout.fillWidth: true
      visible: visibleChildren.length > 0
      spacing: 10
    }

    Hint {
      Layout.leftMargin: 4
      text: root.hint
    }
  }
}
