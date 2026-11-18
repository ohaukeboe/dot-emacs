pragma ComponentBehavior: Bound

// Output or microphone devices and the apps using them, open under their
// row in quick controls. A device can be hidden; hidden ones wait behind a
// "Hidden" row, here and in each app's device pick. Each app has its own
// volume and can be pinned to a device or follow the default.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

Rectangle {
  id: list
  property bool input: false
  readonly property var current: input ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
  readonly property var devices: input ? Rail.audioInputs : Rail.audioOutputs
  // The default device always shows, even when it is on the hidden list.
  readonly property var shown: devices.filter(d => d === current || !Rail.hiddenAudio.includes(d.name))
  readonly property var hidden: devices.filter(d => d !== current && Rail.hiddenAudio.includes(d.name))
  readonly property var apps: Rail.appStreams.filter(s =>
    (s.properties["media.class"] === "Stream/Input/Audio") === input)
  property bool showHidden: false

  function nameOf(node) {
    return node.description || node.nickname || node.name;
  }

  Layout.fillWidth: true
  // Capped like the Wi-Fi list; the rest scrolls.
  implicitHeight: Math.min(column.implicitHeight, 300) + 16
  radius: Config.islandRadius
  color: Config.raised

  Component {
    id: deviceRow
    ListRow {
      required property var modelData
      Layout.fillWidth: true
      activeColor: Config.raised2
      label: list.nameOf(modelData)
      active: modelData === list.current
      action: active ? "" : Rail.hiddenAudio.includes(modelData.name) ? "Show" : "Hide"
      onClicked: {
        if (list.input) Pipewire.preferredDefaultAudioSource = modelData;
        else Pipewire.preferredDefaultAudioSink = modelData;
      }
      onActionClicked: Rail.setAudioHidden(modelData, action === "Hide")
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.margins: 8
    contentHeight: column.implicitHeight
    clip: true

    ColumnLayout {
      id: column
      width: flick.width
      spacing: 2

      CapsuleSlider {
        visible: list.input && list.current !== null
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        color: Config.raised2
        icon: list.current?.audio?.muted ? Icons.micOff : Icons.mic
        value: list.current?.audio?.volume ?? 0
        iconClickable: true
        onMoved: (v) => list.current.audio.volume = v
        onIconClicked: list.current.audio.muted = !list.current.audio.muted
      }

      SectionLabel {
        text: list.input ? "Input" : "Output"
        Layout.leftMargin: 6
      }
      Repeater {
        model: list.shown
        delegate: deviceRow
      }
      ListRow {
        visible: list.hidden.length > 0
        Layout.fillWidth: true
        label: "Hidden (" + list.hidden.length + ")"
        action: list.showHidden ? "Close" : "Open"
        onClicked: list.showHidden = !list.showHidden
        onActionClicked: list.showHidden = !list.showHidden
      }
      Reveal {
        open: list.showHidden && list.hidden.length > 0
        spacing: 2
        Repeater {
          model: list.hidden
          delegate: deviceRow
        }
      }

      SectionLabel {
        visible: list.apps.length > 0
        text: list.input ? "Recording" : "Playing"
        Layout.leftMargin: 6
      }
      Repeater {
        model: list.apps

        ColumnLayout {
          id: app
          required property var modelData
          // The device the app is pinned to; null when it follows the default.
          readonly property var target: Rail.streamTarget(modelData)
          property bool picking: false
          property bool pickHidden: false
          readonly property string targetName: target ? list.nameOf(target) : "Default"
          Layout.fillWidth: true
          Layout.topMargin: 4
          spacing: 6

          function route(device) {
            Rail.routeStream(modelData, device);
            picking = false;
          }

          Component {
            id: routeRow
            ListRow {
              required property var modelData
              Layout.fillWidth: true
              activeColor: Config.raised3
              label: list.nameOf(modelData)
              active: modelData === app.target
              onClicked: app.route(modelData)
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            spacing: 8
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              RailText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.weight: Font.DemiBold
                text: app.modelData.properties["application.name"]
                  || app.modelData.description || app.modelData.name
              }
              Detail {
                Layout.fillWidth: true
                visible: text !== ""
                elide: Text.ElideRight
                text: app.modelData.properties["media.name"] ?? ""
              }
            }
            // Pill has no elide of its own.
            Pill {
              label: app.targetName.length > 18 ? app.targetName.slice(0, 17) + "…" : app.targetName
              on: app.picking
              onClicked: app.picking = !app.picking
            }
          }

          Reveal {
            open: app.picking

            Card {
              padding: 4
              spacing: 0
              radius: Config.pillRadius
              color: Config.raised2

              ListRow {
                Layout.fillWidth: true
                activeColor: Config.raised3
                label: "Default"
                detail: list.current ? list.nameOf(list.current) : ""
                active: app.target === null
                onClicked: app.route(null)
              }
              Repeater {
                model: list.shown
                delegate: routeRow
              }
              ListRow {
                visible: list.hidden.length > 0
                Layout.fillWidth: true
                label: "Hidden (" + list.hidden.length + ")"
                action: app.pickHidden ? "Close" : "Open"
                onClicked: app.pickHidden = !app.pickHidden
                onActionClicked: app.pickHidden = !app.pickHidden
              }
              Repeater {
                model: app.pickHidden ? list.hidden : []
                delegate: routeRow
              }
            }
          }

          CapsuleSlider {
            Layout.fillWidth: true
            color: Config.raised2
            icon: app.modelData.audio?.muted ? (list.input ? Icons.micOff : Icons.volumeOff)
              : (list.input ? Icons.mic : Icons.volume)
            value: app.modelData.audio?.volume ?? 0
            iconClickable: true
            onMoved: (v) => app.modelData.audio.volume = v
            onIconClicked: app.modelData.audio.muted = !app.modelData.audio.muted
          }
        }
      }
    }
  }
}
