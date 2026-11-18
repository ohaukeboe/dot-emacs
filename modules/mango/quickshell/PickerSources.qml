pragma ComponentBehavior: Bound

// The picker's sources layout (Picker.qml; `mango-pick --layout sources`,
// the screencast portal's chooser): "Monitor:" lines as screen cards with a
// live thumbnail, then "Window:" lines as rows with app and tag from Mango.
// Typing in the island's field (PickerIsland.qml) filters the windows; the
// cards stay. Arrows move across the cards and down into the rows
// (Picker.step), Enter, Alt+1 to Alt+9 (cards first) or a click pick.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

ColumnLayout {
  id: sources
  spacing: 8

  readonly property int cardWidth: (Picker.contentWidth - 12) / 2
  readonly property int screenCount: Picker.screenCount
  readonly property var windows: Picker.results.slice(screenCount)

  function screenNamed(name) {
    for (let i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i];
    return null;
  }

  SectionLabel {
    Layout.leftMargin: 4
    visible: sources.screenCount > 0
    text: "Screens"
  }

  GridLayout {
    visible: sources.screenCount > 0
    columns: 2
    columnSpacing: 12
    rowSpacing: 12

    Repeater {
      model: Picker.results.slice(0, sources.screenCount)

      Rectangle {
        id: card
        required property string modelData
        required property int index
        readonly property var info: Picker.source(modelData)
        readonly property var screen: sources.screenNamed(info.name)
        readonly property bool picked: index === Picker.index

        Layout.preferredWidth: sources.cardWidth
        Layout.preferredHeight: content.implicitHeight + 16
        radius: Config.pillRadius
        color: picked ? Config.raised : "transparent"
        border.width: picked ? 2 : 0
        border.color: Config.fg

        HoverArea {
          anchors.fill: parent
          onClicked: Picker.choose(card.index)
        }

        ColumnLayout {
          id: content
          anchors.fill: parent
          anchors.margins: 8
          spacing: 2

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 128
            Layout.bottomMargin: 6
            radius: 10
            color: Config.app
            clip: true

            // The popup exists on every screen; only the shown one captures live.
            ScreencopyView {
              anchors.fill: parent
              visible: card.screen !== null
              captureSource: card.screen
              live: card.screen !== null && card.Window.visibility !== Window.Hidden
            }
          }

          RailText {
            text: card.info.name + (card.index < 9 ? "   Alt+" + (card.index + 1) : "")
            font.weight: Font.DemiBold
          }

          Detail {
            Layout.fillWidth: true
            visible: text !== ""
            text: card.info.description
            elide: Text.ElideRight
          }

          Detail {
            visible: card.screen !== null
            text: card.screen ? Math.round(card.screen.width * card.screen.devicePixelRatio) + "×"
              + Math.round(card.screen.height * card.screen.devicePixelRatio) : ""
          }
        }
      }
    }
  }

  SectionLabel {
    Layout.leftMargin: 4
    visible: sources.windows.length > 0
    text: "Windows"
  }

  Repeater {
    model: sources.windows

    Rectangle {
      id: row
      required property string modelData
      required property int index
      readonly property int at: sources.screenCount + index
      readonly property var info: Picker.source(modelData)
      readonly property bool picked: at === Picker.index

      Layout.preferredWidth: Picker.contentWidth
      Layout.preferredHeight: 40
      radius: Config.pillRadius
      color: picked ? Config.raised : "transparent"

      HoverArea {
        anchors.fill: parent
        onClicked: Picker.choose(row.at)
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: 10

        LetterTile {
          label: row.info.appId || row.info.title
          picked: row.picked
        }

        RailText {
          Layout.fillWidth: true
          text: row.info.title
          font.weight: row.picked ? Font.Bold : Font.Normal
          elide: Text.ElideRight
        }

        Detail {
          text: [row.info.appId, row.info.tags.length > 0 ? "tag " + row.info.tags.join(",") : ""]
            .filter(s => s !== "").join(" · ")
        }

        Hint {
          text: row.at < 9 ? "Alt+" + (row.at + 1) : ""
        }
      }
    }
  }

  Hint {
    Layout.leftMargin: 4
    text: "Arrows move · Enter or Alt+1–9 share · Esc cancel"
  }
}
