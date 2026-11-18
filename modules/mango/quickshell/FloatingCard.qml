pragma ComponentBehavior: Bound

// A card that floats over the screen with a shadow: notification cards and
// the lock screen's password card. Children are placed by the user.
import QtQuick

Rectangle {
  implicitWidth: 360
  radius: Config.cardRadius
  color: Config.island
  layer.enabled: true
  layer.effect: Shadow {}
}
