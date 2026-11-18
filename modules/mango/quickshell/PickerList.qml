pragma ComponentBehavior: Bound

// The picker's popup content (Picker.qml). The list layout, for any caller
// that names no layout or an unknown one, is drawn here: its prompt with a
// filter field, then one row per matching line. A "Kind: name" line shows
// the name with the kind dimmed beside it. Typing filters, Up/Down or
// C-p/C-n move, Enter or Alt+1 to Alt+9 pick, Esc cancels. The tiles,
// sources and clipboard layouts load their own component instead
// (PickerTiles.qml, PickerSources.qml, PickerClip.qml).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
  id: picker
  spacing: 8

  readonly property int rows: 10
  readonly property int rowHeight: 48

  Connections {
    target: Rail
    function onOpenTargetChanged() {
      if (Rail.openTarget !== "picker" || Picker.layout !== "list") return;
      query.text = "";
      query.forceActiveFocus();
    }
  }

  Connections {
    target: Picker
    function onIndexChanged() {
      list.positionViewAtIndex(Picker.index, ListView.Contain);
    }
  }

  // One layout at a time; the list below hides when another is loaded.
  Loader {
    active: Picker.layout !== "list"
    visible: active
    sourceComponent: Picker.layout === "tiles" ? tilesLayout : Picker.layout === "sources" ? sourcesLayout : clipLayout
  }

  Component { id: tilesLayout; PickerTiles {} }
  Component { id: sourcesLayout; PickerSources {} }
  Component { id: clipLayout; PickerClip {} }

  RowLayout {
    visible: Picker.layout === "list"
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    spacing: 12

    SectionLabel {
      Layout.topMargin: 0
      text: Picker.prompt
    }

    QueryInput {
      id: query
      Layout.fillWidth: true
      onTextChanged: Picker.query = text

      Keys.onPressed: (event) => {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        if (event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_P) Picker.move(-1);
        else if (event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_N) Picker.move(1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) Picker.choose(Picker.index);
        else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) Picker.choose(event.key - Qt.Key_1);
        else return;
        event.accepted = true;
      }
      Keys.onEscapePressed: Rail.close()
      placeholder: "Type to filter…"
    }
  }

  ListView {
    id: list
    visible: Picker.layout === "list"
    Layout.preferredWidth: 480
    Layout.preferredHeight: Math.max(1, Math.min(count, picker.rows)) * (picker.rowHeight + spacing) - spacing
    spacing: 2
    clip: true
    model: Picker.results
    boundsBehavior: Flickable.StopAtBounds

    delegate: ListRow {
      required property string modelData
      required property int index
      readonly property string text: Picker.label(modelData)
      readonly property var parts: text.match(/^(\w+): (.*)$/)
      width: ListView.view.width
      label: parts ? parts[2] : text
      action: (parts ? parts[1] : "") + (index < 9 ? "   Alt+" + (index + 1) : "")
      active: index === Picker.index
      onClicked: Picker.choose(index)
    }

    RailText {
      anchors.centerIn: parent
      visible: list.count === 0
      text: "No matches"
      color: Config.dim
    }
  }
}
