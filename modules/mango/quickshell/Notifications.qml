pragma ComponentBehavior: Bound

// Desktop notifications: this shell owns org.freedesktop.Notifications (mako
// is off) and shows each one as an island card under the rail's status
// capsule, newest on top. Normal ones hide after their timeout (5 s by
// default), paused while any card is hovered; critical ones are accent-filled and stay
// until dismissed. One with a "value" hint shows it as a bar and stays until its sender closes it. Left click runs the default action, right click dismisses.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

Scope {
  NotificationServer {
    id: server
    actionsSupported: true
    imageSupported: true
    onNotification: (notification) => notification.tracked = true
  }

  // No screen set: the compositor puts it on the focused output.
  PanelWindow {
    id: window
    // Room around the cards for their shadow.
    readonly property int pad: 32

    // Held as var: qmllint sees the ObjectModel as opaque, so `.values` would warn.
    readonly property var tracked: server.trackedNotifications
    // Cards on screen, newest first. A closed notification stays here until
    // its card has shrunk away, so the ListView never removes a visible item:
    // it leaves a removed delegate frozen where it was, under its neighbours.
    property var shown: []
    readonly property var trackedValues: tracked.values
    onTrackedValuesChanged: shown = trackedValues.filter(n => !shown.includes(n)).reverse().concat(shown)
    function forget(n) { shown = shown.filter(x => x !== n); }
    visible: shown.length > 0
    color: "transparent"
    // Full height: resizing the surface to the cards each frame lags a frame
    // behind and clips cards still sliding. The mask keeps the rest click-through.
    anchors { top: true; right: true; bottom: true }
    implicitWidth: 360 + pad + Config.edgeGap
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "mango-notifications"
    // Only the cards take clicks; the shadow margin passes them through.
    mask: Region { item: list }

    ListView {
      id: list
      x: window.pad
      y: Config.railEdge
      width: 360
      height: contentHeight
      interactive: false
      // ScriptModel diffs, so cards keep their delegates.
      model: ScriptModel { values: window.shown }
      // One handler for the whole stack: hovering any card pauses every timer.
      HoverHandler { id: hover }

      // No ListView transitions: they move each card on its own and let
      // neighbours overlap. Each slot grows and shrinks instead, so the
      // cards below follow it frame by frame.
      delegate: Item {
        id: slot
        required property var modelData
        // 0..1: slot height, and the card's scale and opacity.
        property real progress: 0

        width: 360
        height: progress * (card.height + 8)
        Component.onCompleted: grow.start()

        NumberAnimation { id: grow; target: slot; property: "progress"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        SequentialAnimation {
          id: shrink
          NumberAnimation { target: slot; property: "progress"; to: 0; duration: 200; easing.type: Easing.InOutCubic }
          ScriptAction { script: window.forget(slot.modelData) }
        }
        // The server destroys a closed Notification at once; the lock keeps
        // it alive for the shrink and lets go with the delegate.
        RetainableLock {
          object: slot.modelData
          locked: true
          onDropped: { grow.stop(); shrink.start(); }
        }

        FloatingCard {
          id: card
          readonly property var modelData: slot.modelData

          readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
          readonly property color ink: critical ? Config.onAccent : Config.fg
          readonly property color muted: critical ? Qt.alpha(Config.onAccent, 0.75) : Config.dim
          readonly property var actions: Array.from(modelData.actions)
          readonly property var defaultAction: actions.find(a => a.identifier === "default") ?? null
          readonly property var buttons: actions.filter(a => a.identifier !== "default")
          readonly property string icon: modelData.image !== "" ? modelData.image
            : modelData.appIcon === "" ? ""
            : modelData.appIcon.includes("/") ? modelData.appIcon
            : Quickshell.iconPath(modelData.appIcon, true)
          property int minutes: 0
          // The "value" hint, 0..100: a job in progress (job-view.py). -1 without it.
          readonly property real progress: modelData.hints.value ?? -1

          height: content.implicitHeight + 28
          color: critical ? Config.fg : Config.island
          // Grow out of the status capsule, never past the slot.
          transformOrigin: Item.TopRight
          scale: slot.progress
          opacity: slot.progress

          Timer {
            interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000 : 5000
            running: !card.critical && !hover.hovered && card.progress < 0
            onTriggered: card.modelData.expire()
          }

          Timer {
            interval: 60000
            repeat: true
            running: true
            onTriggered: card.minutes++
          }

          HoverArea {
            anchors.fill: parent
            tint: card.ink
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
              if (mouse.button === Qt.LeftButton && card.defaultAction)
                card.defaultAction.invoke();
              else
                card.modelData.dismiss();
            }
          }

          RowLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors { leftMargin: 16; rightMargin: 14; topMargin: 14 }
            spacing: 12

            Rectangle {
              Layout.alignment: Qt.AlignTop
              implicitWidth: 36
              implicitHeight: 36
              radius: height / 2
              color: card.critical ? Config.onAccent : Config.raised

              Image {
                id: iconImage
                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize: Qt.size(40, 40)
                fillMode: Image.PreserveAspectFit
                source: card.icon
                visible: status === Image.Ready
              }
              Glyph {
                anchors.centerIn: parent
                visible: !iconImage.visible
                text: Icons.bell
                font.pixelSize: Config.iconMedium
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              RailText {
                Layout.fillWidth: true
                text: [card.modelData.appName, card.minutes > 0 ? card.minutes + " min" : "now"]
                  .filter(s => s !== "").join(" · ")
                color: card.muted
                font.pixelSize: Config.fontSmall
                font.weight: Font.DemiBold
                elide: Text.ElideRight
              }
              RailText {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.modelData.summary
                color: card.ink
                font.pixelSize: Config.fontLabel
                font.weight: Font.Bold
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
              RailText {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.modelData.body
                color: card.ink
                lineHeight: 1.15
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
              }
              Meter {
                Layout.topMargin: 6
                visible: card.progress >= 0
                value: card.progress / 100
                fill: card.ink
              }
              Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: card.buttons.length > 0
                spacing: 6
                Repeater {
                  model: card.buttons
                  Pill {
                    required property var modelData
                    label: modelData.text
                    onClicked: modelData.invoke()
                  }
                }
              }
            }

            Rectangle {
              Layout.alignment: Qt.AlignTop
              implicitWidth: 28
              implicitHeight: 28
              radius: height / 2
              color: "transparent"
              Glyph {
                anchors.centerIn: parent
                text: Icons.close
                font.pixelSize: Config.iconSmall
                color: card.muted
              }
              HoverArea {
                anchors.fill: parent
                tint: card.ink
                onClicked: card.modelData.dismiss()
              }
            }
          }
        }
      }
    }
  }
}
