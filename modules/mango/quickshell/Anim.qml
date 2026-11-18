pragma ComponentBehavior: Bound

// The one animation curve: `Behavior on x { Anim {} }`. Set `duration` to
// Config.normal or Config.slow for larger moves.
import QtQuick

NumberAnimation {
  duration: Config.fast
  easing.type: Easing.OutCubic
}
