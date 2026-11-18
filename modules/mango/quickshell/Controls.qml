pragma ComponentBehavior: Bound

// Quick controls: the tiles page, the Wi-Fi, Bluetooth, output and
// microphone lists that open under their rows on it, and the phone detail
// page. Hidden pages take no space, so the card sizes to the open page.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Networking

ColumnLayout {
  width: 308
  spacing: 0

  // Tiles; "wifi", "bluetooth", "output" and "input" are lists inside it.
  Reveal {
    open: ["", "wifi", "bluetooth", "output", "input"].includes(Rail.page)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 10

      CapsuleSlider {
        readonly property var sink: Pipewire.defaultAudioSink
        visible: sink !== null
        Layout.fillWidth: true
        icon: sink?.audio?.muted ? Icons.volumeOff : Icons.volume
        value: sink?.audio?.volume ?? 0
        iconClickable: true
        onMoved: (v) => sink.audio.volume = v
        onIconClicked: sink.audio.muted = !sink.audio.muted
      }

      CapsuleSlider {
        visible: Rail.brightness >= 0
        Layout.fillWidth: true
        icon: Icons.brightness
        value: Rail.brightness / 100
        onMoved: (v) => Rail.setBrightness(v * 100)
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        // Spacing 0 around the Reveals; the rows after the first carry it.
        spacing: 0

        ToggleRow {
          readonly property var current: Rail.wifiNetworks.find(n => n.connected) ?? null
          visible: Networking.wifiHardwareEnabled
          label: "Wi-Fi"
          detail: !Networking.wifiEnabled ? "Off" : current ? current.name : "Not connected"
          icon: Networking.wifiEnabled ? Icons.wifi : Icons.wifiOff
          on: Networking.wifiEnabled
          page: "wifi"
          inline: true
          onToggled: Networking.wifiEnabled = !on
        }

        // Wi-Fi networks, open under the row
        Reveal {
          open: Rail.page === "wifi"
          gap: 4

          Card {
            SectionLabel {
              visible: Networking.wifiEnabled && Rail.wifiNetworks.length > 0
              text: "Networks"
              Layout.leftMargin: 6
            }
            RailText {
              visible: !Networking.wifiEnabled || Rail.wifiNetworks.length === 0
              Layout.margins: 6
              text: Networking.wifiEnabled ? "Scanning…" : "Wi-Fi is off"
              color: Config.dim
            }
            ListView {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(contentHeight, 300)
              visible: Networking.wifiEnabled
              clip: true
              spacing: 2
              model: Rail.wifiNetworks
              delegate: ColumnLayout {
                id: net
                required property var modelData
                property bool askPsk: false
                // WPA-Enterprise: a username as well as a password.
                readonly property bool eap: modelData.security === WifiSecurityType.Wpa2Eap
                  || modelData.security === WifiSecurityType.WpaEap
                property string error: ""
                width: ListView.view.width
                spacing: 0

                function join() {
                  if (psk.text === "" || eap && user.text === "") return;
                  error = "";
                  if (eap) {
                    eapJoin.environment = { WIFI_PASSWORD: psk.text };
                    eapJoin.command = ["sh", "-c", eapJoin.script, "sh",
                      Config.nmcli, modelData.name, user.text];
                    eapJoin.running = true;
                  } else {
                    modelData.connectWithPsk(psk.text);
                  }
                  psk.text = "";
                  askPsk = false;
                }

                onAskPskChanged: if (askPsk) (eap && user.text === "" ? user : psk).focusInput()

                Connections {
                  target: net.modelData
                  function onConnectionFailed(reason) {
                    if (reason === ConnectionFailReason.NoSecrets) net.askPsk = true;
                  }
                }

                // Quickshell can only join with a PSK, so enterprise networks go
                // through nmcli: PEAP with MSCHAPv2, the common setup (eduroam,
                // most offices). The password reaches nmcli on stdin through an
                // environment variable, never on a command line.
                Process {
                  id: eapJoin
                  readonly property string script: `
                    n=$1 ssid=$2 user=$3
                    if "$n" -g connection.id connection show id "$ssid" >/dev/null 2>&1; then
                      "$n" connection modify id "$ssid" 802-1x.identity "$user" || exit
                    else
                      "$n" connection add type wifi con-name "$ssid" ssid "$ssid" \
                        wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 \
                        802-1x.identity "$user" >/dev/null || exit
                    fi
                    printf "802-1x.password:%s\\n" "$WIFI_PASSWORD" |
                      "$n" connection up id "$ssid" passwd-file /dev/stdin >/dev/null`
                  stderr: StdioCollector { id: eapErr }
                  onExited: (code) => {
                    if (code !== 0) net.error = eapErr.text.trim().split("\n").pop() || "Could not connect";
                  }
                }

                // The row and its login fields, lifted into one block while open.
                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: block.implicitHeight + 10 * login.progress
                  radius: Config.pillRadius
                  color: Qt.alpha(Config.raised2, login.progress)

                  ColumnLayout {
                    id: block
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    ListRow {
                      Layout.fillWidth: true
                      activeColor: Config.raised2
                      label: net.modelData.name
                      active: net.modelData.connected
                      detail: [
                        net.modelData.connected ? "connected"
                          : net.modelData.stateChanging || eapJoin.running ? "connecting…"
                          : net.modelData.known ? "saved" : "",
                        net.modelData.security === WifiSecurityType.Open ? "open"
                          : net.eap ? "enterprise" : "secured",
                        Math.round(net.modelData.signalStrength * 100) + "%",
                      ].filter(s => s !== "").join(" · ")
                      action: net.modelData.known ? "Forget" : ""
                      onActionClicked: net.modelData.forget()
                      onClicked: {
                        if (net.modelData.connected)
                          net.modelData.disconnect();
                        else if (!net.modelData.known && net.modelData.security !== WifiSecurityType.Open)
                          net.askPsk = !net.askPsk;
                        else
                          net.modelData.connect();
                      }
                    }

                    Reveal {
                      id: login
                      open: net.askPsk
                      gap: 8
                      spacing: 8

                      TextBox {
                        id: user
                        visible: net.eap
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        placeholder: "Username"
                        onAccepted: psk.focusInput()
                        onCancelled: net.askPsk = false
                      }
                      TextBox {
                        id: psk
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        placeholder: "Password"
                        password: true
                        onAccepted: net.join()
                        onCancelled: net.askPsk = false
                      }
                      RowLayout {
                        Layout.fillWidth: true
                        Layout.rightMargin: 10
                        spacing: 6
                        Item { Layout.fillWidth: true }
                        Pill {
                          label: "Cancel"
                          onClicked: net.askPsk = false
                        }
                        Pill {
                          label: "Join"
                          on: psk.text !== "" && (!net.eap || user.text !== "")
                          onClicked: net.join()
                        }
                      }
                    }
                  }
                }

                Reveal {
                  open: net.error !== ""
                  gap: 6

                  Detail {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    text: net.error
                    wrapMode: Text.Wrap
                  }
                }
              }
            }
          }
        }

        ToggleRow {
          readonly property var adapter: Bluetooth.defaultAdapter
          readonly property int connected: Rail.btDevices.filter(d => d.connected).length
          visible: adapter !== null
          Layout.topMargin: 4
          label: "Bluetooth"
          detail: !on ? "Off" : connected > 0 ? connected + " connected" : "On"
          icon: on ? Icons.bluetooth : Icons.bluetoothOff
          on: adapter?.enabled ?? false
          page: "bluetooth"
          inline: true
          onToggled: adapter.enabled = !on
        }

        // Bluetooth devices, open under the row, with the pairing agent's
        // prompts above them.
        Reveal {
          open: Rail.page === "bluetooth"
          gap: 4

          Card {
            // Kept while closing, so the text does not blank as it shrinks.
            Reveal {
              id: pairing
              readonly property var request: Rail.btPrompt
              property var shown: null
              onRequestChanged: {
                if (!request) return;
                shown = request;
                pairCode.text = "";
                if (request.kind === "pin" || request.kind === "passkey") pairCode.focusInput();
              }
              readonly property string kind: shown?.kind ?? ""
              readonly property bool typed: kind === "pin" || kind === "passkey"
              function submit() {
                if (!typed) Rail.btAnswer("yes");
                else if (pairCode.text !== "") Rail.btAnswer(pairCode.text);
              }
              open: request !== null
              spacing: 8

              RailText {
                Layout.fillWidth: true
                Layout.margins: 6
                Layout.bottomMargin: 0
                wrapMode: Text.Wrap
                readonly property string name: pairing.shown?.name ?? ""
                text: pairing.kind === "confirm" ? `Pair with ${name}? Check that it shows this code.`
                  : pairing.kind === "authorize" ? `Allow ${name} to connect?`
                  : pairing.kind === "pin" ? `Enter the PIN for ${name}.`
                  : pairing.kind === "passkey" ? `Enter the passkey shown on ${name}.`
                  : `Type this code on ${name}, then press Enter.`
              }
              RailText {
                visible: (pairing.shown?.code ?? "") !== ""
                Layout.leftMargin: 6
                text: pairing.shown?.code ?? ""
                font.pixelSize: 24
                font.letterSpacing: 2
              }
              TextBox {
                id: pairCode
                visible: pairing.typed
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                placeholder: pairing.kind === "pin" ? "PIN" : "Passkey"
                onAccepted: pairing.submit()
                onCancelled: Rail.btAnswer("")
              }
              RowLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 6
                Layout.bottomMargin: 6
                spacing: 6
                Item { Layout.fillWidth: true }
                Pill {
                  label: pairing.kind === "display" ? "Hide" : "Reject"
                  onClicked: Rail.btAnswer("")
                }
                Pill {
                  visible: pairing.kind !== "display"
                  label: pairing.typed ? "Pair" : "Accept"
                  on: !pairing.typed || pairCode.text !== ""
                  onClicked: pairing.submit()
                }
              }
            }

            RowLayout {
              visible: Bluetooth.defaultAdapter?.enabled ?? false
              Layout.fillWidth: true
              SectionLabel {
                Layout.fillWidth: true
                text: "Devices"
                Layout.leftMargin: 6
              }
              Pill {
                label: "Scan"
                on: Bluetooth.defaultAdapter?.discovering ?? false
                onClicked: Bluetooth.defaultAdapter.discovering = !on
              }
            }
            RailText {
              visible: !(Bluetooth.defaultAdapter?.enabled ?? false)
              Layout.margins: 6
              text: "Bluetooth is off"
              color: Config.dim
            }
            ListView {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(contentHeight, 300)
              visible: Bluetooth.defaultAdapter?.enabled ?? false
              clip: true
              spacing: 2
              model: Rail.btDevices
              delegate: ListRow {
                id: dev
                required property var modelData
                // Set when the user paired from here, to connect once pairing ends.
                property bool connectAfterPair: false
                width: ListView.view.width
                activeColor: Config.raised2
                label: modelData.name
                active: modelData.connected
                detail: [
                  modelData.pairing ? "pairing…"
                    : modelData.connected ? "connected"
                    : modelData.paired ? "paired" : "",
                  modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : "",
                ].filter(s => s !== "").join(" · ")
                action: modelData.paired || modelData.bonded ? "Unpair" : ""
                onActionClicked: modelData.forget()
                onClicked: {
                  if (modelData.connected) {
                    modelData.disconnect();
                  } else if (modelData.paired) {
                    modelData.connect();
                  } else {
                    connectAfterPair = true;
                    modelData.trusted = true;
                    modelData.pair();
                  }
                }

                Connections {
                  target: dev.modelData
                  function onPairedChanged() {
                    if (dev.connectAfterPair && dev.modelData.paired) {
                      dev.connectAfterPair = false;
                      dev.modelData.connect();
                    }
                  }
                }
              }
            }
          }
        }

        ToggleRow {
          readonly property var sink: Pipewire.defaultAudioSink
          visible: sink !== null
          Layout.topMargin: 4
          label: "Output"
          detail: sink ? sink.description || sink.nickname || sink.name : ""
          icon: on ? Icons.volume : Icons.volumeOff
          on: !(sink?.audio?.muted ?? true)
          page: "output"
          inline: true
          onToggled: sink.audio.muted = on
        }

        // Output devices and playing apps, open under the row
        Reveal {
          open: Rail.page === "output"
          gap: 4
          AudioList {}
        }

        ToggleRow {
          readonly property var source: Pipewire.defaultAudioSource
          visible: source !== null
          Layout.topMargin: 4
          label: "Microphone"
          detail: !on ? "Muted" : source.description || source.nickname || source.name
          icon: on ? Icons.mic : Icons.micOff
          on: !(source?.audio?.muted ?? true)
          page: "input"
          inline: true
          onToggled: source.audio.muted = on
        }

        // Input devices and recording apps, open under the row
        Reveal {
          open: Rail.page === "input"
          gap: 4
          AudioList { input: true }
        }
      }

      // Phone card and its actions (Phone.qml exists only with KDE Connect).
      Loader {
        Layout.fillWidth: true
        Layout.topMargin: 4
        source: Config.kdeconnect ? "Phone.qml" : ""
      }

      Segmented {
        readonly property var profiles: PowerProfiles.hasPerformanceProfile
          ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
          : [PowerProfile.PowerSaver, PowerProfile.Balanced]
        options: PowerProfiles.hasPerformanceProfile
          ? ["Saver", "Balanced", "Performance"] : ["Saver", "Balanced"]
        current: profiles.indexOf(PowerProfiles.profile)
        onPicked: (i) => PowerProfiles.profile = profiles[i]
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 8

        Glyph {
          visible: UPower.displayDevice.isLaptopBattery
          text: Icons.plug
          font.pixelSize: Config.iconMedium
        }
        RailText {
          visible: UPower.displayDevice.isLaptopBattery
          Layout.fillWidth: true
          textFormat: Text.StyledText
          text: "<b>" + Math.round(UPower.displayDevice.percentage * 100) + "%</b>"
            + "<font color=\"" + Config.dim + "\"> · "
            + (UPower.displayDevice.state === UPowerDeviceState.Charging ? "Charging"
              : UPower.displayDevice.state === UPowerDeviceState.FullyCharged ? "Full"
              : "On battery") + "</font>"
        }
        Item {
          visible: !UPower.displayDevice.isLaptopBattery
          Layout.fillWidth: true
        }
        IconButton {
          icon: Icons.lock
          onClicked: {
            Rail.close();
            Rail.run([Config.lock]);
          }
        }
        IconButton {
          icon: Icons.power
          onClicked: {
            Rail.close();
            Rail.run([Config.powerMenu]);
          }
        }
      }
    }
  }

  // Phone detail page
  Reveal {
    open: Rail.page === "phone"

    Loader {
      Layout.fillWidth: true
      Component.onCompleted: if (Config.kdeconnect) setSource("Phone.qml", { page: true })
    }
  }
}
