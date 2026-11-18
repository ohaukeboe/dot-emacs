pragma ComponentBehavior: Bound

// A Nerd Font icon from Icons.
import QtQuick

Text {
  // Distance-field rendering (the default) leaves colour fringes at these sizes.
  renderType: Text.NativeRendering
  color: Config.fg
  font.family: Config.iconFont
  font.pixelSize: Config.icon
}
