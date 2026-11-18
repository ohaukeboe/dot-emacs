pragma ComponentBehavior: Bound

// The large clock and date over the lock screen's and the greeter's card.
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
  spacing: 2

  SystemClock {
    id: time
    precision: SystemClock.Minutes
  }

  RailText {
    Layout.alignment: Qt.AlignHCenter
    font.pixelSize: Config.fontDisplay
    font.weight: Font.Light
    text: Qt.formatTime(time.date, "HH:mm")
  }
  Detail {
    Layout.alignment: Qt.AlignHCenter
    font.pixelSize: Config.fontHeading
    font.weight: Font.DemiBold
    text: Qt.formatDate(time.date, "dddd d MMMM")
  }
}
