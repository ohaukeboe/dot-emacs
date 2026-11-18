pragma ComponentBehavior: Bound

// The picker's popup content (Picker.qml). The list layout, for any caller
// that names no layout or an unknown one, is drawn here: one row per
// matching line under the search field in the island (PickerIsland.qml,
// which has the keys). A "Kind: name" line shows the name with the kind
// dimmed beside it. The tiles, sources and clipboard layouts load their own
// component instead (PickerTiles.qml, PickerSources.qml, PickerClip.qml).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
  id: picker
  spacing: 8

  readonly property int rows: 10
  readonly property int rowHeight: 48

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

  ListView {
    id: list
    visible: Picker.layout === "list"
    Layout.preferredWidth: Picker.contentWidth
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
