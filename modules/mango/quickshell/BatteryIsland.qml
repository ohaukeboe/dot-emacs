pragma ComponentBehavior: Bound

// The battery glyph and level on an island: the lock screen's and the
// greeter's top-right corner. Hidden without a laptop battery.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

Island {
  visible: UPower.displayDevice.isLaptopBattery
  width: battery.implicitWidth + 28

  RowLayout {
    id: battery
    anchors.centerIn: parent
    spacing: 6

    Glyph {
      font.pixelSize: Config.iconMedium
      text: Icons.battery(UPower.displayDevice)
    }
    RailText {
      font.weight: Font.DemiBold
      text: Math.round(UPower.displayDevice.percentage * 100) + "%"
    }
  }
}
