pragma ComponentBehavior: Bound

// The drop shadow under a floating card: `layer.enabled: true` and
// `layer.effect: Shadow {}`.
import QtQuick.Effects

MultiEffect {
  shadowEnabled: true
  shadowColor: "#80000000"
  shadowBlur: 1.0
  shadowVerticalOffset: 8
}
