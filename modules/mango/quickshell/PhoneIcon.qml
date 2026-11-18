pragma ComponentBehavior: Bound

// The rail's phone icon, shown while a paired KDE Connect device is reachable
// (specs/014-quickshell-rail research R9). Bar.qml loads this file only when
// KDE Connect is enabled; the build drops it otherwise, like Phone.qml.
import QtQuick
import org.kde.kdeconnect as KDEConnect

Item {
  id: root
  // Device id to reachable-and-paired, kept by the delegates below.
  property var up: ({})
  readonly property int reachable: Object.values(up).filter(u => u).length
  visible: reachable > 0
  implicitWidth: visible ? Config.railItem : 0
  implicitHeight: Config.railItem

  KDEConnect.DevicesModel { id: devices }

  Instantiator {
    id: rows
    model: devices
    delegate: QtObject {
      required property string deviceId
      readonly property var device: KDEConnect.DeviceDbusInterfaceFactory.create(deviceId)
      readonly property bool up: device.isPaired && device.isReachable
      onUpChanged: root.mark(deviceId, up)
      Component.onCompleted: root.mark(deviceId, up)
      Component.onDestruction: root.mark(deviceId, false)
    }
  }

  function mark(id, value) {
    const next = Object.assign({}, up);
    next[id] = value;
    up = next;
  }

  Glyph {
    anchors.centerIn: parent
    text: Icons.phone
    font.family: Config.railIconFont
    font.pixelSize: Config.iconMedium
  }
}
