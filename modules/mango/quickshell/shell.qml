pragma ComponentBehavior: Bound

// Popups for the Mango rail (specs/012-mango-rail-bar): quick controls and a
// calendar. The rail itself is waybar; it toggles these over IPC:
//   qs -c mango ipc call controls toggle
//   qs -c mango ipc call calendar toggle
// The at-sign placeholders are store paths and colours (modules/mango).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Networking

ShellRoot {
  id: root

  readonly property color bg: "#@bg@"
  readonly property color card: "#@card@"
  readonly property color accent: "#@accent@"
  readonly property color fg: "#c8c5c7"
  readonly property color dim: "#888888"
  // Rail width plus the outer gap, so the card sits beside the rail.
  readonly property int railEdge: 32 + 14

  // "" (closed), "controls" or "calendar"; one popup at a time.
  property string openTarget: ""
  property string openOutput: ""
  property string pendingTarget: ""

  function toggle(target) {
    if (openTarget === target) {
      openTarget = "";
      return;
    }
    // The pointer is on the rail that was clicked, so its monitor is the one.
    pendingTarget = target;
    cursorQuery.running = true;
  }

  function close() {
    openTarget = "";
  }

  // Quick-controls detail page: "" (tiles), "wifi", "bluetooth" or "sound".
  property string page: ""
  onPageChanged: {
    const adapter = Bluetooth.defaultAdapter;
    if (page !== "bluetooth" && adapter && adapter.discovering)
      adapter.discovering = false;
  }

  // Held as var: qmllint sees these ObjectModels as opaque, so `.values` would warn.
  readonly property var netDevices: Networking.devices
  readonly property var pwNodes: Pipewire.nodes
  readonly property var wifiDevice:
    netDevices.values.find(d => d.type === DeviceType.Wifi) ?? null
  // Connected first, then saved, then strongest.
  readonly property var wifiNetworks: (wifiDevice?.networks.values ?? []).slice().sort((a, b) =>
    (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
  readonly property var btDevices: (Bluetooth.defaultAdapter?.devices.values ?? []).slice().sort((a, b) =>
    (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

  readonly property var audioNodes: pwNodes.values.filter(n => n.audio)
  readonly property var audioOutputs: audioNodes.filter(n => !n.isStream && n.isSink)
  readonly property var audioInputs: audioNodes.filter(n => !n.isStream && !n.isSink)
  readonly property var audioStreams: audioNodes.filter(n => n.isStream)
  // Filter chains (echo cancel) are virtual streams, not apps. Properties
  // fill in once the tracker below binds the streams.
  readonly property var appStreams:
    audioStreams.filter(n => n.properties["node.virtual"] !== "true")

  Binding {
    when: root.wifiDevice !== null
    target: root.wifiDevice
    property: "scannerEnabled"
    value: root.openTarget === "controls" && root.page === "wifi"
  }

  PwObjectTracker {
    objects: root.openTarget === "controls" && root.page === "sound" ? root.audioStreams : []
  }

  Process {
    id: cursorQuery
    command: ["@mmsg@", "get", "cursorpos"]
    stdout: StdioCollector {
      onStreamFinished: {
        let monitor = "";
        try {
          monitor = JSON.parse(this.text).monitor || "";
        } catch (e) {}
        root.openOutput = monitor;
        root.openTarget = root.pendingTarget;
      }
    }
  }

  IpcHandler {
    target: "controls"
    function toggle(): void { root.toggle("controls"); }
  }

  IpcHandler {
    target: "calendar"
    function toggle(): void { root.toggle("calendar"); }
  }

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
  }

  // brightnessctl -m prints "device,class,current,percent%,max".
  property int brightness: -1
  Process {
    id: brightnessRead
    command: ["@brightnessctl@", "-m", "--class=backlight"]
    stdout: StdioCollector {
      onStreamFinished: {
        const fields = this.text.trim().split(",");
        root.brightness = fields.length >= 4 ? parseInt(fields[3]) : -1;
      }
    }
    onExited: (code) => { if (code !== 0) root.brightness = -1; }
  }

  onOpenTargetChanged: {
    page = "";
    if (openTarget === "controls") brightnessRead.running = true;
  }

  component RailPopup: PanelWindow {
    id: popup
    required property var modelData
    required property string target
    default property alias content: contentBox.data
    property bool bottomAligned: false

    screen: modelData
    // Unknown output (null from mmsg): show on every screen rather than none.
    visible: root.openTarget === target
      && (root.openOutput === "" || root.openOutput === modelData.name
          || !Quickshell.screens.some(s => s.name === root.openOutput))
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "mango-popup"

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
    }

    Rectangle {
      id: cardBox
      x: root.railEdge
      y: popup.bottomAligned ? parent.height - height - 14 : (parent.height - height) / 2
      // Sized from contentBox, not its own childrenRect: the MouseArea below
      // fills the card, which would make that a binding loop.
      width: contentBox.childrenRect.width + 32
      height: contentBox.childrenRect.height + 32
      radius: 14
      color: root.card

      // Swallows clicks on the card's empty space so they do not close it.
      MouseArea { anchors.fill: parent }

      Item { id: contentBox }
    }
  }

  component RailText: Text {
    color: root.fg
    font.pixelSize: 13
  }

  component Toggle: Rectangle {
    id: toggle
    property string label
    property bool on
    // Detail page the arrow opens; "" for no arrow.
    property string page: ""
    signal clicked()
    implicitWidth: 92
    implicitHeight: 36
    radius: 18
    color: on ? root.accent : root.bg
    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: toggle.page !== "" ? -7 : 0
      text: toggle.label
      color: toggle.on ? root.bg : root.fg
      font.pixelSize: 12
    }
    MouseArea { anchors.fill: parent; onClicked: toggle.clicked() }
    Arrow {
      visible: toggle.page !== ""
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      page: toggle.page
      color: toggle.on ? root.bg : root.fg
    }
  }

  // "›" that opens a quick-controls detail page.
  component Arrow: Text {
    id: arrow
    property string page
    text: "›"
    color: root.fg
    font.pixelSize: 18
    MouseArea {
      anchors.fill: parent
      anchors.margins: -6
      onClicked: root.page = arrow.page
    }
  }

  component PageHeader: RowLayout {
    id: header
    property string title
    Layout.fillWidth: true
    RailText {
      text: "‹"
      font.pixelSize: 20
      MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.page = "" }
    }
    RailText { text: header.title; font.pixelSize: 16; Layout.fillWidth: true }
  }

  // One entry in a detail-page list: name, dim detail, optional side action.
  component ListRow: Rectangle {
    id: row
    property string label
    property string detail
    property bool active
    property string action: ""
    signal clicked()
    signal actionClicked()
    implicitWidth: 300
    implicitHeight: 40
    radius: 10
    color: active ? root.bg : "transparent"
    MouseArea { anchors.fill: parent; onClicked: row.clicked() }
    ColumnLayout {
      anchors.left: parent.left
      anchors.right: actionText.left
      anchors.leftMargin: 10
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      RailText {
        Layout.fillWidth: true
        text: row.label
        color: row.active ? root.accent : root.fg
        elide: Text.ElideRight
      }
      RailText {
        visible: text !== ""
        text: row.detail
        color: root.dim
        font.pixelSize: 11
      }
    }
    RailText {
      id: actionText
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: row.action
      color: root.dim
      font.pixelSize: 11
      MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: row.actionClicked() }
    }
  }

  component SectionLabel: RailText {
    color: root.dim
    font.pixelSize: 11
    Layout.topMargin: 4
  }

  Variants {
    model: Quickshell.screens

    RailPopup {
      target: "controls"
      bottomAligned: true

      // Hidden pages take no space, so the card sizes to the open page.
      ColumnLayout {
        x: 16
        y: 16
        width: 300
        spacing: 0

        ColumnLayout {
          visible: root.page === ""
          Layout.fillWidth: true
          spacing: 12

          // Battery
          RowLayout {
            visible: UPower.displayDevice.isLaptopBattery
            RailText {
              text: Math.round(UPower.displayDevice.percentage * 100) + "%"
              font.pixelSize: 28
            }
            RailText {
              text: UPower.displayDevice.state === UPowerDeviceState.Charging ? "charging"
                : UPower.displayDevice.state === UPowerDeviceState.FullyCharged ? "full"
                : "on battery"
              color: root.dim
            }
          }

          // Volume
          RowLayout {
            visible: Pipewire.defaultAudioSink !== null
            RailText { text: "Volume"; Layout.preferredWidth: 80 }
            Slider {
              Layout.fillWidth: true
              from: 0; to: 1
              value: Pipewire.defaultAudioSink?.audio?.volume ?? 0
              onMoved: Pipewire.defaultAudioSink.audio.volume = value
            }
            Arrow { page: "sound" }
          }

          // Brightness
          RowLayout {
            visible: root.brightness >= 0
            RailText { text: "Brightness"; Layout.preferredWidth: 80 }
            Slider {
              Layout.fillWidth: true
              from: 1; to: 100
              value: root.brightness
              onMoved: {
                root.brightness = Math.round(value);
                Quickshell.execDetached(["@brightnessctl@", "--class=backlight", "set", root.brightness + "%"]);
              }
            }
          }

          // Toggles
          GridLayout {
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            Toggle {
              visible: Pipewire.defaultAudioSource !== null
              label: "Mic"
              on: !(Pipewire.defaultAudioSource?.audio?.muted ?? true)
              onClicked: Pipewire.defaultAudioSource.audio.muted = on
            }
            Toggle {
              visible: Networking.wifiHardwareEnabled
              label: "Wi-Fi"
              page: "wifi"
              on: Networking.wifiEnabled
              onClicked: Networking.wifiEnabled = !on
            }
            Toggle {
              visible: Bluetooth.defaultAdapter !== null
              label: "Bluetooth"
              page: "bluetooth"
              on: Bluetooth.defaultAdapter?.enabled ?? false
              onClicked: Bluetooth.defaultAdapter.enabled = !on
            }
          }

          // Power profile
          RowLayout {
            spacing: 8
            Toggle {
              label: "Saver"
              on: PowerProfiles.profile === PowerProfile.PowerSaver
              onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
            }
            Toggle {
              label: "Balanced"
              on: PowerProfiles.profile === PowerProfile.Balanced
              onClicked: PowerProfiles.profile = PowerProfile.Balanced
            }
            Toggle {
              visible: PowerProfiles.hasPerformanceProfile
              label: "Perform."
              on: PowerProfiles.profile === PowerProfile.Performance
              onClicked: PowerProfiles.profile = PowerProfile.Performance
            }
          }

          Toggle {
            label: "Power…"
            on: false
            onClicked: {
              root.close();
              Quickshell.execDetached(["@powerMenu@"]);
            }
          }
        }

        // Wi-Fi detail page
        ColumnLayout {
          visible: root.page === "wifi"
          Layout.fillWidth: true
          spacing: 6

          PageHeader { title: "Wi-Fi" }
          RailText {
            visible: !Networking.wifiEnabled || root.wifiNetworks.length === 0
            text: Networking.wifiEnabled ? "Scanning…" : "Wi-Fi is off"
            color: root.dim
          }
          ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 320)
            visible: Networking.wifiEnabled
            clip: true
            spacing: 2
            model: root.wifiNetworks
            delegate: ColumnLayout {
              id: net
              required property var modelData
              property bool askPsk: false
              width: 300
              spacing: 4

              Connections {
                target: net.modelData
                function onConnectionFailed(reason) {
                  if (reason === ConnectionFailReason.NoSecrets) net.askPsk = true;
                }
              }

              ListRow {
                Layout.fillWidth: true
                label: net.modelData.name
                active: net.modelData.connected
                detail: [
                  net.modelData.connected ? "connected"
                    : net.modelData.stateChanging ? "connecting…"
                    : net.modelData.known ? "saved" : "",
                  net.modelData.security === WifiSecurityType.Open ? "open" : "secured",
                  Math.round(net.modelData.signalStrength * 100) + "%",
                ].filter(s => s !== "").join(" · ")
                action: net.modelData.known ? "Forget" : ""
                onActionClicked: net.modelData.forget()
                onClicked: {
                  if (net.modelData.connected)
                    net.modelData.disconnect();
                  else if (!net.modelData.known && net.modelData.security !== WifiSecurityType.Open)
                    net.askPsk = true;
                  else
                    net.modelData.connect();
                }
              }

              RowLayout {
                visible: net.askPsk
                Layout.fillWidth: true
                TextField {
                  id: psk
                  Layout.fillWidth: true
                  placeholderText: "Password"
                  echoMode: TextInput.Password
                  onVisibleChanged: if (visible) forceActiveFocus()
                  onAccepted: join.clicked()
                  Keys.onEscapePressed: net.askPsk = false
                }
                Toggle {
                  id: join
                  label: "Join"
                  implicitWidth: 60
                  on: psk.text !== ""
                  onClicked: {
                    if (psk.text === "") return;
                    net.modelData.connectWithPsk(psk.text);
                    psk.text = "";
                    net.askPsk = false;
                  }
                }
              }
            }
          }
        }

        // Bluetooth detail page; PIN and passkey prompts come from blueman-applet.
        ColumnLayout {
          visible: root.page === "bluetooth"
          Layout.fillWidth: true
          spacing: 6

          RowLayout {
            Layout.fillWidth: true
            PageHeader { title: "Bluetooth" }
            Toggle {
              visible: Bluetooth.defaultAdapter?.enabled ?? false
              label: "Scan"
              implicitWidth: 60
              on: Bluetooth.defaultAdapter?.discovering ?? false
              onClicked: Bluetooth.defaultAdapter.discovering = !on
            }
          }
          RailText {
            visible: !(Bluetooth.defaultAdapter?.enabled ?? false)
            text: "Bluetooth is off"
            color: root.dim
          }
          ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 320)
            visible: Bluetooth.defaultAdapter?.enabled ?? false
            clip: true
            spacing: 2
            model: root.btDevices
            delegate: ListRow {
              id: dev
              required property var modelData
              // Set when the user paired from here, to connect once pairing ends.
              property bool connectAfterPair: false
              width: 300
              label: modelData.name
              active: modelData.connected
              detail: [
                modelData.pairing ? "pairing…"
                  : modelData.connected ? "connected"
                  : modelData.paired ? "paired" : "",
                modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : "",
              ].filter(s => s !== "").join(" · ")
              action: modelData.paired ? "Forget" : ""
              onActionClicked: modelData.forget()
              onClicked: {
                if (modelData.connected) {
                  modelData.disconnect();
                } else if (modelData.paired) {
                  modelData.connect();
                } else {
                  connectAfterPair = true;
                  modelData.trusted = true;
                  modelData.pair();
                }
              }

              Connections {
                target: dev.modelData
                function onPairedChanged() {
                  if (dev.connectAfterPair && dev.modelData.paired) {
                    dev.connectAfterPair = false;
                    dev.modelData.connect();
                  }
                }
              }
            }
          }
        }

        // Sound detail page
        ColumnLayout {
          visible: root.page === "sound"
          Layout.fillWidth: true
          spacing: 4

          PageHeader { title: "Sound" }

          SectionLabel { text: "Output" }
          Repeater {
            model: root.audioOutputs
            ListRow {
              required property var modelData
              Layout.fillWidth: true
              label: modelData.description || modelData.nickname || modelData.name
              active: modelData === Pipewire.defaultAudioSink
              onClicked: Pipewire.preferredDefaultAudioSink = modelData
            }
          }

          SectionLabel { text: "Input"; visible: root.audioInputs.length > 0 }
          Repeater {
            model: root.audioInputs
            ListRow {
              required property var modelData
              Layout.fillWidth: true
              label: modelData.description || modelData.nickname || modelData.name
              active: modelData === Pipewire.defaultAudioSource
              onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
          }

          SectionLabel { text: "Apps"; visible: root.appStreams.length > 0 }
          Repeater {
            model: root.appStreams
            ColumnLayout {
              id: stream
              required property var modelData
              Layout.fillWidth: true
              spacing: 0
              RowLayout {
                Layout.fillWidth: true
                RailText {
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: (stream.modelData.properties["application.name"]
                         || stream.modelData.description || stream.modelData.name)
                    + (stream.modelData.properties["media.class"] === "Stream/Input/Audio"
                     ? " (recording)" : "")
                }
                Toggle {
                  label: "Mute"
                  implicitWidth: 56
                  implicitHeight: 26
                  on: stream.modelData.audio?.muted ?? false
                  onClicked: stream.modelData.audio.muted = !on
                }
              }
              Slider {
                Layout.fillWidth: true
                from: 0; to: 1
                value: stream.modelData.audio?.volume ?? 0
                onMoved: stream.modelData.audio.volume = value
              }
            }
          }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    RailPopup {
      id: calendarPopup
      target: "calendar"

      property date today: new Date()
      property int month: today.getMonth()
      property int year: today.getFullYear()
      onVisibleChanged: if (visible) {
        today = new Date();
        month = today.getMonth();
        year = today.getFullYear();
      }

      function step(delta) {
        const d = new Date(year, month + delta, 1);
        month = d.getMonth();
        year = d.getFullYear();
      }

      ColumnLayout {
        x: 16
        y: 16
        spacing: 8

        RowLayout {
          Layout.fillWidth: true
          RailText {
            Layout.fillWidth: true
            text: Qt.locale().standaloneMonthName(calendarPopup.month) + " " + calendarPopup.year
            font.pixelSize: 16
          }
          RailText {
            text: "‹"
            font.pixelSize: 18
            MouseArea { anchors.fill: parent; onClicked: calendarPopup.step(-1) }
          }
          RailText {
            text: "›"
            font.pixelSize: 18
            MouseArea { anchors.fill: parent; onClicked: calendarPopup.step(1) }
          }
        }

        GridLayout {
          columns: 2

          Item { width: 1; height: 1 }
          DayOfWeekRow {
            locale: grid.locale
            Layout.fillWidth: true
            delegate: RailText {
              required property string shortName
              text: shortName
              color: root.dim
              horizontalAlignment: Text.AlignHCenter
            }
          }

          WeekNumberColumn {
            month: grid.month
            year: grid.year
            locale: grid.locale
            Layout.fillHeight: true
            delegate: RailText {
              required property int weekNumber
              text: weekNumber
              color: root.dim
              verticalAlignment: Text.AlignVCenter
            }
          }
          MonthGrid {
            id: grid
            month: calendarPopup.month
            year: calendarPopup.year
            locale: Qt.locale()
            Layout.fillWidth: true
            delegate: Rectangle {
              required property var model
              readonly property bool isToday: model.today
              implicitWidth: 32
              implicitHeight: 28
              radius: 14
              color: isToday ? root.accent : "transparent"
              Text {
                anchors.centerIn: parent
                text: parent.model.day
                font.pixelSize: 13
                color: parent.isToday ? root.bg
                  : parent.model.month === grid.month ? root.fg : root.dim
              }
            }
          }
        }
      }
    }
  }
}
