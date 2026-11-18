pragma ComponentBehavior: Bound

// A rail capsule: the surface every rail island is drawn on.
import QtQuick

Rectangle {
  height: Config.railHeight
  radius: Config.islandRadius
  color: Config.island
}
