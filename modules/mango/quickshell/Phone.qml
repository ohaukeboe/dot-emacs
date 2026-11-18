pragma ComponentBehavior: Bound

// KDE Connect in quick controls (specs/013-mango-islands-shell, stories 3
// and 4): the phone card under the toggles, or with `page` set, the phone
// detail page. Controls.qml loads this file only when KDE Connect is enabled,
// so nothing else imports org.kde.kdeconnect.
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kdeconnect as KDEConnect

ColumnLayout {
  id: root
  property bool page: false

  // Every device the daemon knows, paired or not, as {deviceId, name, device}.
  property var all: []
  readonly property var paired: all.filter(d => d.device.isPaired)
  // The phone picked on the detail page if it is still reachable, else the
  // first reachable paired device, else the first paired one.
  readonly property var phone:
    paired.find(d => d.deviceId === Rail.phoneId && d.device.isReachable)
      ?? paired.find(d => d.device.isReachable) ?? paired[0] ?? null
  readonly property string phoneId: phone?.deviceId ?? ""
  readonly property bool reachable: phone?.device.isReachable ?? false
  readonly property var battery: batteryPlugin.available
    ? KDEConnect.DeviceBatteryDbusInterfaceFactory.create(phoneId) : null
  readonly property string status: !reachable ? "Not reachable" : [
    "Connected",
    battery ? battery.charge + "%" : "",
    root.page ? (battery?.isCharging ? "charging" : "")
      : notifications.count === 1 ? "1 notification"
      : notifications.count > 1 ? notifications.count + " notifications" : "",
  ].filter(s => s !== "").join(" · ")

  spacing: 10

  KDEConnect.DevicesModel { id: devices }

  Instantiator {
    id: rows
    model: devices
    delegate: QtObject {
      required property string deviceId
      required property string name
      readonly property var device: KDEConnect.DeviceDbusInterfaceFactory.create(deviceId)
    }
    onObjectAdded: root.collect()
    onObjectRemoved: root.collect()
  }

  function collect() {
    const list = [];
    for (let i = 0; i < rows.count; ++i)
      if (rows.objectAt(i)) list.push(rows.objectAt(i));
    all = list;
  }

  KDEConnect.PluginChecker {
    id: batteryPlugin
    pluginName: "battery"
    device: root.phone?.device ?? null
    onDeviceChanged: pluginsChanged()
  }

  KDEConnect.NotificationsModel {
    id: notifications
    deviceId: root.phoneId
  }

  function ring() { KDEConnect.FindMyPhoneDbusInterfaceFactory.create(phoneId).ring(); }
  function sendClipboard() { KDEConnect.ClipboardDbusInterfaceFactory.create(phoneId).sendClipboard(); }
  // The popup holds exclusive keyboard focus, so it closes before the dialog.
  function sendFile() {
    Rail.close();
    fileDialog.open();
  }
  // The daemon mounts the phone and opens the mount in the file manager.
  function browse() {
    Rail.close();
    KDEConnect.SftpDbusInterfaceFactory.create(phoneId).startBrowsing();
  }

  FileDialog {
    id: fileDialog
    title: "Send to " + (root.phone?.name ?? "phone")
    fileMode: FileDialog.OpenFiles
    onAccepted: {
      const share = KDEConnect.ShareDbusInterfaceFactory.create(root.phoneId);
      for (const url of selectedFiles) share.shareUrl(url.toString());
    }
  }

  // A phone action: icon over a label on the card, side by side on the page.
  component Action: Rectangle {
    id: action
    property string icon
    property string label
    property bool wide: false
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: wide ? 48 : 52
    radius: wide ? 16 : 14
    // One step above the raised card it sits on.
    color: wide ? Config.raised : Config.raised2
    opacity: root.reachable ? 1 : 0.4

    GridLayout {
      x: action.wide ? 14 : (parent.width - width) / 2
      anchors.verticalCenter: parent.verticalCenter
      columns: action.wide ? 2 : 1
      rowSpacing: 4
      columnSpacing: 10
      Glyph {
        Layout.alignment: Qt.AlignHCenter
        text: action.icon
        font.pixelSize: Config.iconMedium
      }
      RailText {
        Layout.alignment: Qt.AlignHCenter
        text: action.label
        font.pixelSize: action.wide ? Config.fontBody : Config.fontCaption
        font.weight: Font.DemiBold
      }
    }

    HoverArea {
      anchors.fill: parent
      enabled: root.reachable
      onClicked: action.clicked()
    }
  }

  // Phone card
  ToggleRow {
    visible: !root.page && root.phone === null
    label: "Set up phone"
    detail: "Pair through KDE Connect"
    icon: Icons.phone
    page: "phone"
    onToggled: Rail.page = "phone"
  }

  Card {
    visible: !root.page && root.phone !== null
    padding: 12
    spacing: 10

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      IconButton {
        size: 44
        icon: Icons.phone
        on: true
      }
      Item {
        Layout.fillWidth: true
        implicitHeight: 44

        ColumnLayout {
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.right: arrow.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0
          RailText {
            Layout.fillWidth: true
            text: root.phone?.name ?? ""
            font.pixelSize: Config.fontLabel
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Detail {
            Layout.fillWidth: true
            text: root.status
            elide: Text.ElideRight
          }
        }
        Glyph {
          id: arrow
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: Icons.chevronRight
          color: Config.dim
        }
        HoverArea {
          anchors.fill: parent
          radius: Config.pillRadius
          onClicked: Rail.page = "phone"
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      Action { icon: Icons.ring; label: "Ring"; onClicked: root.ring() }
      Action { icon: Icons.upload; label: "Send file"; onClicked: root.sendFile() }
      Action { icon: Icons.clipboard; label: "Clipboard"; onClicked: root.sendClipboard() }
      Action { icon: Icons.folder; label: "Browse"; onClicked: root.browse() }
    }
  }

  // Detail page
  PageHeader {
    visible: root.page
    title: "KDE Connect"
  }

  Rectangle {
    visible: root.page && root.phone !== null
    Layout.fillWidth: true
    implicitHeight: 76
    radius: Config.islandRadius
    color: Config.raised

    RowLayout {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12
      IconButton {
        size: 52
        icon: Icons.phone
        on: true
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Title {
          Layout.fillWidth: true
          text: root.phone?.name ?? ""
          elide: Text.ElideRight
        }
        Detail {
          text: root.status
        }
      }
    }
  }

  GridLayout {
    visible: root.page && root.phone !== null
    Layout.fillWidth: true
    columns: 2
    rowSpacing: 8
    columnSpacing: 8
    Action { icon: Icons.ring; label: "Ring phone"; wide: true; onClicked: root.ring() }
    Action { icon: Icons.upload; label: "Send file"; wide: true; onClicked: root.sendFile() }
    Action { icon: Icons.clipboard; label: "Send clipboard"; wide: true; onClicked: root.sendClipboard() }
    Action { icon: Icons.folder; label: "Browse files"; wide: true; onClicked: root.browse() }
  }

  // Notifications mirrored from the phone
  RowLayout {
    visible: root.page && root.phone !== null
    Layout.fillWidth: true
    SectionLabel {
      Layout.fillWidth: true
      text: "Notifications"
    }
    Detail {
      visible: notifications.isAnyDimissable
      Layout.topMargin: 6
      text: "Clear all"
      font.weight: Font.DemiBold
      HoverArea {
        anchors.fill: parent
        anchors.margins: -6
        onClicked: notifications.dismissAll()
      }
    }
  }
  RailText {
    visible: root.page && root.phone !== null && notifications.count === 0
    text: "No notifications"
    color: Config.dim
  }
  ListView {
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(contentHeight, 300)
    visible: count > 0
    clip: true
    spacing: root.spacing
    model: root.page ? notifications : null
    delegate: Rectangle {
      id: note
      required property string appName
      required property string title
      required property string notitext
      required property bool dismissable
      required property var dbusInterface
      width: ListView.view.width
      implicitHeight: noteText.implicitHeight + 20
      radius: Config.pillRadius
      color: Config.raised

      RowLayout {
        id: noteText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 12
        spacing: 12

        Rectangle {
          Layout.alignment: Qt.AlignTop
          implicitWidth: 32
          implicitHeight: 32
          radius: height / 2
          // One step above the raised row, as on the phone card.
          color: Config.raised2
          Glyph {
            anchors.centerIn: parent
            text: Icons.message
            font.pixelSize: Config.iconMedium
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0
          RailText {
            Layout.fillWidth: true
            text: note.appName
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Detail {
            Layout.fillWidth: true
            visible: text !== ""
            // KDE Connect often repeats the app name as the title.
            text: [note.title, note.notitext]
              .filter(t => t !== "" && t !== note.appName).join(" · ")
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }
        }
      }

      HoverArea {
        anchors.fill: parent
        enabled: note.dismissable
        onClicked: note.dbusInterface.dismiss()
      }
    }
  }

  // Other paired devices; tapping a reachable one makes it the phone.
  SectionLabel {
    visible: root.page && root.paired.length > 1
    text: "Other devices"
  }
  Repeater {
    model: root.page ? root.paired.filter(d => d !== root.phone) : []
    ListRow {
      required property var modelData
      Layout.fillWidth: true
      label: modelData.name
      detail: modelData.device.isReachable ? "Connected" : "Paired · not reachable"
      action: "Forget"
      onClicked: if (modelData.device.isReachable) Rail.phoneId = modelData.deviceId
      onActionClicked: modelData.device.unpair()
    }
  }

  // Reachable devices that are not paired yet.
  SectionLabel {
    visible: root.page
    text: "Pair a new device"
  }
  RailText {
    visible: root.page && unpaired.count === 0
    text: "Open KDE Connect on the phone, on the same network"
    color: Config.dim
    wrapMode: Text.Wrap
    Layout.fillWidth: true
  }
  Repeater {
    id: unpaired
    model: root.page ? root.all.filter(d => !d.device.isPaired && d.device.isReachable) : []
    ListRow {
      required property var modelData
      Layout.fillWidth: true
      label: modelData.name
      detail: modelData.device.isPairRequested ? "Pairing…" : ""
      onClicked: modelData.device.requestPairing()
    }
  }
}
