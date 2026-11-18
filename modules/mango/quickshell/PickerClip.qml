pragma ComponentBehavior: Bound

// The picker's clipboard layout (Picker.qml; `mango-pick --layout clipboard`,
// Super+v): a search capsule with the match count, the cliphist rows with
// type and size, and a preview of the selected entry. Rows and the preview
// decode their entry through cliphist on demand. Typing filters, Up/Down or
// C-p/C-n move, Enter pastes, Ctrl+Enter copies only, Delete forgets the
// entry, Alt+1 to Alt+9 pick, Esc cancels.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
  id: pane
  spacing: 8

  readonly property int rows: 8
  readonly property int rowHeight: 48
  readonly property string line: Picker.results[Picker.index] ?? ""
  readonly property var entry: Picker.clip(line)
  readonly property string imageDir: Quickshell.env("XDG_RUNTIME_DIR") + "/mango-pick"
  // Preview state for `line`: decoded text, an image file URL, or failed.
  property string previewText: ""
  property string previewImage: ""
  property bool previewFailed: false
  // Bumped per preview; a superseded process's late exit or output is dropped.
  property int previewSeq: 0

  function detail(e, lines) {
    if (e.kind === "image") return e.format + " · " + e.width + "×" + e.height + " · " + e.size;
    return lines === undefined ? "text" : "text · " + lines + (lines === 1 ? " line" : " lines");
  }

  function takeFocus() {
    if (Rail.openTarget !== "picker") return;
    query.text = "";
    query.forceActiveFocus();
  }

  Component.onCompleted: {
    takeFocus();
    showPreview();
  }

  function showPreview() {
    previewText = "";
    previewImage = "";
    previewFailed = false;
    previewSeq++;
    if (line === "") return;
    if (entry.kind === "image") {
      imagePreview.seq = previewSeq;
      imagePreview.path = imageDir + "/" + entry.id;
      imagePreview.exec(["/bin/sh", "-c", 'mkdir -p "$3" && printf "%s\\n" "$1" | "$2" decode > "$3/$4"',
        "sh", line, Config.cliphist, imageDir, entry.id]);
    } else {
      textPreview.seq = previewSeq;
      textPreview.exec(["/bin/sh", "-c", 'printf "%s\\n" "$1" | "$2" decode | head -c 65536',
        "sh", line, Config.cliphist]);
    }
  }

  onLineChanged: showPreview()

  Connections {
    target: Rail
    function onOpenTargetChanged() {
      pane.takeFocus();
    }
  }

  Connections {
    target: Picker
    function onIndexChanged() {
      list.positionViewAtIndex(Picker.index, ListView.Contain);
    }
  }

  Process {
    id: textPreview
    property int seq: 0
    stdout: StdioCollector {
      onStreamFinished: if (textPreview.seq === pane.previewSeq) pane.previewText = this.text
    }
    onExited: (code) => {
      if (seq === pane.previewSeq) pane.previewFailed = code !== 0;
    }
  }

  Process {
    id: imagePreview
    property string path: ""
    property int seq: 0
    onExited: (code) => {
      if (seq !== pane.previewSeq) return;
      if (code === 0) pane.previewImage = "file://" + path;
      else pane.previewFailed = true;
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 40
    radius: height / 2
    color: Config.raised

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      spacing: 10

      Glyph {
        text: Icons.search
        color: Config.dim
        font.pixelSize: Config.iconMedium
      }

      RailText {
        text: Picker.prompt
        color: Config.dim
        font.weight: Font.DemiBold
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
          else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && ctrl) Picker.chooseAlt(Picker.index);
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) Picker.choose(Picker.index);
          else if (event.key === Qt.Key_Delete) Picker.forget(Picker.index);
          else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) Picker.choose(event.key - Qt.Key_1);
          else return;
          event.accepted = true;
        }
        Keys.onEscapePressed: Rail.close()
        placeholder: "Type to search…"
      }

      Detail {
        text: Picker.results.length + " of " + Picker.items.length
      }
    }
  }

  RowLayout {
    spacing: 12

    ListView {
      id: list
      Layout.preferredWidth: 300
      Layout.preferredHeight: pane.rows * pane.rowHeight + (pane.rows - 1) * spacing
      spacing: 2
      clip: true
      model: Picker.results
      boundsBehavior: Flickable.StopAtBounds

      // Each row counts its entry's lines once, the first time it is shown.
      delegate: ListRow {
        id: row
        required property string modelData
        required property int index
        readonly property var entry: Picker.clip(modelData)
        width: ListView.view.width
        label: entry.kind === "image" ? "Image" : entry.preview
        detail: pane.detail(entry, Picker.lineCounts[entry.id])
        active: index === Picker.index
        onClicked: Picker.choose(index)

        Process {
          id: counter
          // awk, unlike wc -l, counts a last line without a newline.
          command: ["/bin/sh", "-c", 'printf "%s\\n" "$1" | "$2" decode | awk "END { print NR }"',
            "sh", row.modelData, Config.cliphist]
          stdout: StdioCollector {
            onStreamFinished: Picker.countLines(row.entry.id, parseInt(this.text) || 0)
          }
        }

        Component.onCompleted: {
          if (entry.kind === "text" && Picker.lineCounts[entry.id] === undefined) counter.running = true;
        }
      }

      RailText {
        anchors.centerIn: parent
        visible: list.count === 0
        text: "No matches"
        color: Config.dim
      }
    }

    Rectangle {
      Layout.preferredWidth: 360
      Layout.fillHeight: true
      radius: Config.pillRadius
      color: Config.app
      clip: true

      Flickable {
        id: textView
        anchors.fill: parent
        anchors.margins: 12
        visible: pane.entry.kind === "text" && !pane.previewFailed
        contentHeight: previewLabel.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Text {
          id: previewLabel
          width: textView.width
          text: pane.previewText
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
          renderType: Text.NativeRendering
          color: Config.fg
          font.family: "monospace"
          font.pixelSize: Config.fontSmall
        }
      }

      Image {
        anchors.fill: parent
        anchors.margins: 12
        visible: pane.entry.kind === "image" && !pane.previewFailed
        source: pane.previewImage
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        // A file Qt cannot decode falls back to the detail line too.
        onStatusChanged: if (status === Image.Error) pane.previewFailed = true
      }

      // A failed decode shows the row's detail line instead.
      RailText {
        anchors.centerIn: parent
        visible: pane.previewFailed
        text: pane.detail(pane.entry, Picker.lineCounts[pane.entry.id])
        color: Config.dim
      }
    }
  }

  Hint {
    Layout.leftMargin: 10
    text: "Enter paste · Ctrl+Enter copy only · Del forget · Esc close"
  }
}
