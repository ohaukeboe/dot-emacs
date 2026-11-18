pragma ComponentBehavior: Bound

// The picker's sources layout (Picker.qml; `mango-pick --layout sources`,
// the screencast portal's chooser): "Monitor:" lines as screen cards with a
// live thumbnail, then "Window:" lines as rows with app and tag from Mango.
// Typing filters the windows; the cards stay. Arrows move across the cards
// and down into the rows, Enter, Alt+1 to Alt+9 (cards first) or a click
// pick, Esc cancels.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

ColumnLayout {
  id: sources
  spacing: 8

  readonly property int cardWidth: 240
  readonly property int screenCount: Picker.results.filter(l => l.startsWith("Monitor:")).length
  readonly property var windows: Picker.results.slice(screenCount)

  function takeFocus() {
    if (Rail.openTarget !== "picker") return;
    query.text = "";
    query.forceActiveFocus();
  }

  Component.onCompleted: takeFocus()

  Connections {
    target: Rail
    function onOpenTargetChanged() {
      sources.takeFocus();
    }
  }

  function screenNamed(name) {
    for (let i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i];
    return null;
  }

  // Cards sit two per row; Up/Down step a row of cards, then into the rows.
  function step(key) {
    const i = Picker.index;
    const n = screenCount;
    const last = Picker.results.length - 1;
    let next = i;
    if (i < n) {
      if (key === Qt.Key_Left) next = Math.max(0, i - 1);
      else if (key === Qt.Key_Right) next = Math.min(n - 1, i + 1);
      else if (key === Qt.Key_Up) next = i >= 2 ? i - 2 : i;
      else next = i + 2 < n ? i + 2 : Math.min(n, last);
    } else if (key === Qt.Key_Up) {
      next = i === n ? Math.max(0, n - 1) : i - 1;
    } else if (key === Qt.Key_Down) {
      next = Math.min(last, i + 1);
    } else {
      return false;
    }
    Picker.index = next;
    return true;
  }

  RailText {
    Layout.leftMargin: 4
    text: Picker.prompt
    font.pixelSize: Config.fontTitle
    font.weight: Font.DemiBold
  }

  QueryInput {
    id: query
    Layout.fillWidth: true
    Layout.leftMargin: 4
    onTextChanged: Picker.query = text

    Keys.onPressed: (event) => {
      const alt = (event.modifiers & Qt.AltModifier) !== 0;
      if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(event.key)) {
        if (!sources.step(event.key)) return;
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) Picker.choose(Picker.index);
      else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) Picker.choose(event.key - Qt.Key_1);
      else return;
      event.accepted = true;
    }
    Keys.onEscapePressed: Rail.close()
    placeholder: "Type to filter windows…"
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

      Layout.preferredWidth: 2 * sources.cardWidth + 12
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
