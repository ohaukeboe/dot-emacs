pragma ComponentBehavior: Bound

import QtQuick

Text {
  // Distance-field rendering (the default) leaves colour fringes at these sizes.
  renderType: Text.NativeRendering
  color: Config.fg
  font.pixelSize: Config.fontBody
}
