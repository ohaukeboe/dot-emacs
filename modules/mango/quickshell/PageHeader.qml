pragma ComponentBehavior: Bound

// Back button and title of a quick-controls detail page.
import QtQuick
import QtQuick.Layouts

RowLayout {
  id: header
  property string title
  Layout.fillWidth: true
  spacing: 10

  IconButton {
    icon: Icons.chevronLeft
    onClicked: Rail.page = ""
  }
  RailText {
    text: header.title
    font.pixelSize: Config.fontHeading
    font.weight: Font.Bold
    Layout.fillWidth: true
  }
}
