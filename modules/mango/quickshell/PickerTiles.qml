pragma ComponentBehavior: Bound

// The picker's tiles layout (Picker.qml; `mango-pick --layout tiles`), for a
// short fixed menu such as the power menu: one wrapping row of icon tiles,
// no filter. Each line is label<TAB>icon[<TAB>confirm]; icon names a glyph
// in Icons. A confirm tile arms on the first pick ("Press N again") and
// returns on the second. Left/Right move, Enter, 1-9 or a click pick, Esc
// cancels.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
  id: tiles
  spacing: 12

  readonly property int count: Picker.results.length

  function takeFocus() {
    if (Rail.openTarget === "picker") tiles.forceActiveFocus();
  }

  Component.onCompleted: takeFocus()

  Connections {
    target: Rail
    function onOpenTargetChanged() {
      tiles.takeFocus();
    }
  }

  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Left) Picker.move(-1);
    else if (event.key === Qt.Key_Right) Picker.move(1);
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) Picker.pick(Picker.index);
    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < tiles.count) Picker.pick(event.key - Qt.Key_1);
    else if (event.key === Qt.Key_Escape) Rail.close();
    else {
      Picker.armed = -1;
      return;
    }
    event.accepted = true;
  }

  SectionLabel {
    Layout.leftMargin: 4
    Layout.topMargin: 0
    text: Picker.prompt
  }

  Flow {
    id: row
    // Wraps past six tiles rather than growing wider than the screen.
    Layout.preferredWidth: Math.max(1, Math.min(tiles.count, 6)) * (96 + row.spacing) - row.spacing
    spacing: 8

    Repeater {
      model: Picker.results

      Rectangle {
        id: tile
        required property string modelData
        required property int index
        readonly property var fields: modelData.split("\t")
        readonly property bool picked: index === Picker.index
        readonly property string glyph: {
          const g = Icons[fields[1] ?? ""];
          return typeof g === "string" && g !== "" ? g : Icons.generic;
        }

        width: 96
        height: 104
        radius: Config.islandRadius
        color: Config.raised
        border.width: picked ? 2 : 0
        border.color: Config.fg

        HoverArea {
          anchors.fill: parent
          onClicked: Picker.pick(tile.index)
        }

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 6

          Glyph {
            Layout.alignment: Qt.AlignHCenter
            text: tile.glyph
            font.pixelSize: 28
          }

          RailText {
            Layout.alignment: Qt.AlignHCenter
            text: tile.fields[0]
            font.weight: tile.picked ? Font.Bold : Font.Medium
          }

          RailText {
            Layout.alignment: Qt.AlignHCenter
            text: Picker.armed === tile.index ? "Press " + (tile.index + 1) + " again"
              : tile.index < 9 ? String(tile.index + 1) : ""
            color: Picker.armed === tile.index ? Config.fg : Config.dim
            font.pixelSize: Config.fontCaption
          }
        }
      }
    }
  }

  Hint {
    Layout.leftMargin: 4
    text: "← → move · Enter or 1–" + Math.min(tiles.count, 9) + " pick · Esc cancel"
  }
}
