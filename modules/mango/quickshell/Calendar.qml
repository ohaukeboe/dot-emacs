pragma ComponentBehavior: Bound

// The calendar under the clock: month, week numbers, today as an accent circle.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
  id: calendar
  spacing: 10

  property date today: new Date()
  property int month: today.getMonth()
  property int year: today.getFullYear()

  function step(delta) {
    const d = new Date(year, month + delta, 1);
    month = d.getMonth();
    year = d.getFullYear();
  }

  Connections {
    target: Rail
    function onOpenTargetChanged() {
      if (Rail.openTarget !== "calendar") return;
      calendar.today = new Date();
      calendar.month = calendar.today.getMonth();
      calendar.year = calendar.today.getFullYear();
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 6
    Title {
      Layout.fillWidth: true
      text: Qt.locale().standaloneMonthName(calendar.month) + " " + calendar.year
    }
    IconButton {
      size: 32
      icon: Icons.chevronLeft
      onClicked: calendar.step(-1)
    }
    IconButton {
      size: 32
      icon: Icons.chevronRight
      onClicked: calendar.step(1)
    }
  }

  GridLayout {
    columns: 2
    columnSpacing: 4
    rowSpacing: 2

    Item { width: 1; height: 1 }
    DayOfWeekRow {
      locale: grid.locale
      Layout.fillWidth: true
      delegate: Detail {
        required property string shortName
        text: shortName
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
      }
    }

    WeekNumberColumn {
      month: grid.month
      year: grid.year
      locale: grid.locale
      Layout.fillHeight: true
      delegate: Detail {
        required property int weekNumber
        text: weekNumber
        verticalAlignment: Text.AlignVCenter
      }
    }
    MonthGrid {
      id: grid
      month: calendar.month
      year: calendar.year
      locale: Qt.locale()
      Layout.fillWidth: true
      delegate: Rectangle {
        required property var model
        readonly property bool isToday: model.today
        implicitWidth: 34
        implicitHeight: 32
        radius: height / 2
        color: isToday ? Config.fg : "transparent"
        Text {
          anchors.centerIn: parent
          text: parent.model.day
          font.pixelSize: Config.fontSmall
          font.weight: parent.isToday ? Font.Bold : Font.Normal
          color: parent.isToday ? Config.onAccent
            : parent.model.month === grid.month ? Config.fg : Config.dim
        }
      }
    }
  }
}
