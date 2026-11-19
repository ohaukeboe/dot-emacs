pragma ComponentBehavior: Bound

// The displays card (specs/018-display-layout-card): a floating card in the
// middle of the screen with the layout of the connected displays on top
// (DisplayCanvas.qml), the selected display's settings below, and Apply.
// After an Apply it asks whether to keep the layout and reverts when the
// ten seconds run out. State and every program call are in Displays.qml.
// Enter applies or keeps, Esc closes or reverts, Tab picks the next display.
// Since specs/020-duplicate-display a switch over the layout picks an
// arrangement (Extend, Duplicate, Only panel, Only external), also with the
// left and right arrow keys, and a display that copies another can be
// separated from its stack or made its source.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "displayLayout.mjs" as Geo

PanelWindow {
  id: win
  required property var modelData

  readonly property bool open: Displays.open && Rail.showsOn(modelData.name)
  readonly property bool idle: Displays.phase === "idle"
  readonly property bool confirming: Displays.phase === "confirming"
  readonly property var display: Displays.current
  // 0 closed, 1 open.
  property real shown: open ? 1 : 0
  Behavior on shown { Anim { duration: Config.normal } }

  // Esc and a click outside: revert while the question is up, else close.
  function cancel() {
    if (confirming) Displays.revert();
    else Rail.close();
  }

  function accept() {
    if (confirming) Displays.keep();
    else Displays.apply();
  }

  function hz(refresh) {
    return Math.round(refresh) + " Hz";
  }

  function labelOf(name) {
    const d = Displays.pending.find(o => o.name === name);
    return d ? Geo.label(d) : name;
  }

  // The selected display's stack, source first; one name when it has none.
  readonly property var members: {
    if (!display || !display.enabled) return [];
    const source = Geo.sourceOf(Displays.pending, display.name);
    return [source].concat(Geo.copiesOf(Displays.pending, source).map(d => d.name));
  }
  readonly property bool isCopy: (display?.enabled ?? false) && display.copyOf !== ""
  // Open lists of choices; the arrow keys wait while one is open.
  property int listsOpen: 0
  readonly property var arrangementLabels: ({
    extend: "Extend", duplicate: "Duplicate", panel: "Only panel", external: "Only external",
  })

  screen: modelData
  visible: shown > 0
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.namespace: "mango-displays"

  // A closed row that opens a list of choices under it. The list floats
  // over `host`, so opening it moves nothing and the card keeps its size.
  // The host is the whole window, not the card: the card is a layer and
  // would clip a list that reaches past its bottom edge.
  component Chooser: Item {
    id: chooser
    property string text
    property var options: []
    property int currentIndex: -1
    property bool expanded: false
    property Item host: null
    signal picked(int index)

    implicitHeight: 40

    // Rows shown at once; the rest scrolls.
    property int rows: 1

    onExpandedChanged: {
      if (!expanded || host === null) return;
      const p = mapToItem(host, 0, height + 6);
      // Six rows, or as many as fit above the screen's bottom edge.
      const fit = Math.floor((host.height - p.y - Config.edgeGap - 12 + 2) / 38);
      rows = Math.max(1, Math.min(options.length, 6, fit));
      list.x = p.x;
      list.y = p.y;
      view.positionViewAtIndex(Math.max(0, currentIndex), ListView.Contain);
    }

    Connections {
      target: Displays
      function onPhaseChanged() { chooser.expanded = false; }
      function onSelectedChanged() { chooser.expanded = false; }
      function onOpenChanged() { chooser.expanded = false; }
    }

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: Config.raised2

      RailText {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: chooser.text
        font.pixelSize: Config.fontSmall
        font.weight: Font.DemiBold
      }
      Glyph {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.chevronRight
        color: Config.dim
        font.pixelSize: Config.iconSmall
        rotation: chooser.expanded ? 90 : 0
        Behavior on rotation { Anim {} }
      }
      HoverArea {
        anchors.fill: parent
        onClicked: chooser.expanded = !chooser.expanded
      }
    }

    // A click anywhere else closes the list and nothing more.
    MouseArea {
      parent: chooser.host
      anchors.fill: parent
      z: 9
      visible: chooser.expanded
      onClicked: chooser.expanded = false
    }

    Rectangle {
      id: list
      parent: chooser.host
      z: 10
      width: chooser.width
      height: view.height + 12
      radius: Config.islandRadius
      color: Config.raised2
      visible: opacity > 0
      opacity: chooser.expanded ? 1 : 0
      Behavior on opacity { Anim {} }
      layer.enabled: true
      layer.effect: Shadow {}

      ListView {
        id: view
        x: 6
        y: 6
        width: parent.width - 12
        height: chooser.rows * 38 - 2
        spacing: 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: chooser.options

        delegate: ListRow {
          required property string modelData
          required property int index
          width: ListView.view.width
          height: 36
          label: modelData
          active: index === chooser.currentIndex
          activeColor: Config.raised3
          onClicked: {
            chooser.picked(index);
            chooser.expanded = false;
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: win.open
    onClicked: win.cancel()
  }

  Item {
    id: stage
    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: win.cancel()
    Keys.onReturnPressed: win.accept()
    Keys.onEnterPressed: win.accept()
    Keys.onTabPressed: { if (win.idle) Displays.selectNext(1); }
    Keys.onBacktabPressed: { if (win.idle) Displays.selectNext(-1); }
    Keys.onLeftPressed: { if (win.idle && win.listsOpen === 0) Displays.arrangeStep(-1); }
    Keys.onRightPressed: { if (win.idle && win.listsOpen === 0) Displays.arrangeStep(1); }

    FloatingCard {
      id: card
      anchors.centerIn: parent
      width: 640
      height: column.implicitHeight + 24
      opacity: win.shown
      scale: 0.96 + 0.04 * win.shown

      // Swallows clicks on the card's empty space so they do not close it.
      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 6
          Layout.rightMargin: 6
          Layout.topMargin: 2
          spacing: 12

          Title { text: "Displays" }
          Detail {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: Displays.status !== "" ? Displays.status
              : Displays.setup === "undocked" ? "Undocked"
              : Displays.setup !== "" ? "Setup: " + Displays.setup
              : "No saved setup matches"
          }
        }

        Segmented {
          visible: Displays.choices.length > 0
          enabled: win.idle
          options: Displays.choices.map(c => win.arrangementLabels[c])
          current: Displays.choices.indexOf(Displays.arrangement)
          onPicked: (index) => Displays.arrange(Displays.choices[index])
        }

        DisplayCanvas {
          Layout.fillWidth: true
          Layout.preferredHeight: 240
          enabled: win.idle
        }

        Card {
          visible: win.display !== null
          enabled: win.idle
          padding: 12
          spacing: 12

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Title {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: win.display ? Geo.label(win.display) : ""
              }
              Detail {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: {
                  const d = win.display;
                  if (!d) return "";
                  if (!d.enabled) return d.name + " · Off";
                  const m = d.modes[d.mode];
                  const mode = m.width + "×" + m.height + " · " + win.hz(m.refresh);
                  if (d.copyOf !== "") return d.name + " · Duplicates " + win.labelOf(d.copyOf) + " · " + mode;
                  const copies = Geo.copiesOf(Displays.pending, d.name);
                  return d.name + " · " + mode + " · " + d.scale + "×"
                    + (copies.length > 0 ? " · Shown on " + copies.map(c => Geo.label(c)).join(", ") : "");
                }
              }
            }
            Pill {
              visible: win.isCopy
              color: Config.raised2
              label: "Separate"
              onClicked: Displays.separate(win.display.name)
            }
            Pill {
              visible: win.isCopy
              color: Config.raised2
              label: "Make source"
              onClicked: Displays.makeSource(win.display.name)
            }
            Pill {
              visible: win.display?.enabled ?? false
              color: on ? Config.fg : Config.raised2
              label: "Adaptive sync"
              on: win.display?.adaptiveSync ?? false
              onClicked: Displays.setAdaptiveSync(win.display.name, !win.display.adaptiveSync)
            }
            Pill {
              color: on ? Config.fg : Config.raised2
              label: on ? "On" : "Off"
              on: win.display?.enabled ?? false
              onClicked: Displays.setEnabled(win.display.name, !win.display.enabled)
            }
          }

          // The displays of the selected one's stack; a click selects.
          RowLayout {
            visible: win.members.length > 1
            Layout.fillWidth: true
            spacing: 6

            Detail { text: "Stack" }
            Repeater {
              model: win.members
              Pill {
                required property string modelData
                color: on ? Config.fg : Config.raised2
                label: win.labelOf(modelData)
                on: modelData === Displays.selected
                onClicked: Displays.selected = modelData
              }
            }
            Item { Layout.fillWidth: true }
          }

          GridLayout {
            id: grid
            visible: win.display?.enabled ?? false
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 6

            readonly property var display: win.display
            readonly property var mode: display ? display.modes[display.mode] : null
            readonly property var sizes: display ? Geo.resolutions(display) : []
            readonly property var rateModes: mode ? Geo.rates(display, mode.width, mode.height) : []
            readonly property var scaleOptions: {
              const list = Geo.scales.slice();
              if (display && !list.includes(display.scale)) list.push(display.scale);
              return list.sort((a, b) => a - b);
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.alignment: Qt.AlignTop
              spacing: 6
              SectionLabel { text: "Resolution"; Layout.topMargin: 0 }
              Chooser {
                host: stage
                onExpandedChanged: win.listsOpen += expanded ? 1 : -1
                Layout.fillWidth: true
                text: grid.mode ? grid.mode.width + "×" + grid.mode.height : ""
                options: grid.sizes.map(s => s.w + "×" + s.h)
                currentIndex: grid.mode
                  ? grid.sizes.findIndex(s => s.w === grid.mode.width && s.h === grid.mode.height) : -1
                onPicked: (index) => Displays.setResolution(grid.display.name, grid.sizes[index].w, grid.sizes[index].h)
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.alignment: Qt.AlignTop
              spacing: 6
              SectionLabel { text: "Refresh rate"; Layout.topMargin: 0 }
              Segmented {
                visible: grid.rateModes.length <= 4
                color: Config.raised2
                options: grid.display ? grid.rateModes.map(i => win.hz(grid.display.modes[i].refresh)) : []
                current: grid.display ? grid.rateModes.indexOf(grid.display.mode) : -1
                onPicked: (index) => Displays.setMode(grid.display.name, grid.rateModes[index])
              }
              Chooser {
                host: stage
                onExpandedChanged: win.listsOpen += expanded ? 1 : -1
                visible: grid.rateModes.length > 4
                Layout.fillWidth: true
                text: grid.mode ? win.hz(grid.mode.refresh) : ""
                options: grid.display ? grid.rateModes.map(i => grid.display.modes[i].refresh.toFixed(2) + " Hz") : []
                currentIndex: grid.display ? grid.rateModes.indexOf(grid.display.mode) : -1
                onPicked: (index) => Displays.setMode(grid.display.name, grid.rateModes[index])
              }
            }

            ColumnLayout {
              // A copy shows its source's picture at the source's scale.
              visible: !win.isCopy
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: 6
              SectionLabel { text: "Scale" }
              Segmented {
                color: Config.raised2
                options: grid.scaleOptions.map(s => s + "×")
                current: grid.display ? grid.scaleOptions.indexOf(grid.display.scale) : -1
                onPicked: (index) => Displays.setScale(grid.display.name, grid.scaleOptions[index])
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: 6
              SectionLabel { text: "Rotation" }
              Segmented {
                color: Config.raised2
                glyph: Icons.monitor
                options: [0, 90, 180, 270]
                current: grid.display ? Geo.rotation(grid.display.transform) / 90 : -1
                onPicked: (index) => Displays.setRotation(grid.display.name, index * 90)
              }
            }
          }
        }

        RowLayout {
          visible: !win.confirming
          Layout.fillWidth: true
          Layout.leftMargin: 6
          Layout.rightMargin: 6
          spacing: 8

          Hint {
            Layout.fillWidth: true
            text: "← → arrangement · Tab next display · Drop on a display to duplicate · Enter applies"
            elide: Text.ElideRight
          }
          Pill {
            label: "Copy as setup"
            enabled: win.idle
            onClicked: Displays.copySetup()
          }
          Pill {
            label: "Apply"
            on: Displays.dirty
            enabled: win.idle && Displays.dirty
            opacity: Displays.dirty ? 1 : 0.5
            onClicked: Displays.apply()
          }
        }

        RowLayout {
          visible: win.confirming
          Layout.fillWidth: true
          Layout.leftMargin: 6
          Layout.rightMargin: 6
          spacing: 8

          RailText {
            Layout.fillWidth: true
            textFormat: Text.StyledText
            text: "Keep this layout? Reverting in <b>" + Displays.secondsLeft + "</b> s"
          }
          Pill {
            label: "Revert"
            onClicked: Displays.revert()
          }
          Pill {
            label: "Keep"
            on: true
            onClicked: Displays.keep()
          }
        }
      }
    }
  }
}
