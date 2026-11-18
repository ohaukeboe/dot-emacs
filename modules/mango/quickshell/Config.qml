pragma Singleton
pragma ComponentBehavior: Bound

// The design tokens (README.md) and every build-time value the popups need
// (specs/013-mango-islands-shell). This is the only file with at-sign
// placeholders: modules/mango fills them with the palette and store paths,
// and the build fails on a missing one.
import QtQuick
import Quickshell

Singleton {
  readonly property color frame: "#@frame@"
  readonly property color app: "#@app@"
  readonly property color island: "#@island@"
  readonly property color raised: "#@raised@"
  readonly property color fg: "#@fg@"
  readonly property color dim: "#@dim@"
  readonly property color onAccent: "#@onAccent@"
  // Surfaces on a raised card: one and two steps lighter, and a text field.
  readonly property color raised2: Qt.lighter(raised, 1.16)
  readonly property color raised3: Qt.lighter(raised, 1.32)
  readonly property color field: Qt.lighter(raised, 1.5)

  readonly property string mmsg: "@mmsg@"
  // Steps a display's layout cycle (the rail's layout glyph).
  readonly property string mangoLayout: "@mangoLayout@"
  readonly property string btAgent: "@btAgent@"
  readonly property string nmcli: "@nmcli@"
  // Pins apps to audio devices (Rail.routeStream).
  readonly property string pwMetadata: "@pwMetadata@"
  readonly property string brightnessctl: "@brightnessctl@"
  readonly property string cliphist: "@cliphist@"
  // Proton Pass quick access (Pass.qml): the backend and its clipboard timeout.
  readonly property string passBackend: "@passBackend@"
  readonly property string passClearSecs: "@passClearSecs@"
  readonly property string powerMenu: "@powerMenu@"
  readonly property string lock: "@lock@"
  readonly property string systemctl: "@systemctl@"
  readonly property string systemdRun: "@systemdRun@"
  readonly property string terminal: "@terminal@"
  // Empty when Claude Code is not enabled; hides "Open Claude".
  readonly property string claude: "@claude@"
  // Phone card and page in quick controls (Phone.qml).
  readonly property bool kdeconnect: @kdeconnect@

  readonly property string iconFont: "Symbols Nerd Font"
  // The rail keeps waybar's fonts: fontconfig's sans-serif for text and the
  // Mono symbols font, whose glyphs fill the cell, for icons.
  readonly property string railFont: "sans-serif"
  readonly property string railIconFont: "Symbols Nerd Font Mono"
  // Rail capsules (Bar.qml): 8 px from the top, 36 px tall, then the same
  // 8 px gap before popups. These were waybar's height and margins.
  readonly property int railTop: 8
  readonly property int railHeight: 36
  readonly property int railEdge: railTop + railHeight + 8
  // A rail item's cell inside an island (status icons, tray cells).
  readonly property int railItem: 28
  // Radii: popup and notification cards, islands and raised cards, rows and
  // small pills, small tiles. Capsules and circles use height / 2.
  readonly property int cardRadius: 22
  readonly property int islandRadius: 18
  readonly property int pillRadius: 14
  readonly property int chipRadius: 8
  // Text sizes (RailText is fontBody; Hint, Detail and Title set theirs).
  readonly property int fontCaption: 11
  readonly property int fontSmall: 12
  readonly property int fontBody: 13
  readonly property int fontLabel: 14
  readonly property int fontTitle: 15
  readonly property int fontHeading: 16
  // The lock screen's clock.
  readonly property int fontDisplay: 112
  // Glyph sizes (Glyph is icon).
  readonly property int iconSmall: 14
  readonly property int iconMedium: 16
  readonly property int icon: 18
  // Animation lengths in ms (Anim is fast): hover and fades, content that
  // opens or resizes, islands that bloom.
  readonly property int fast: 120
  readonly property int normal: 180
  readonly property int slow: 240
  // The launcher's card, and its search island once open.
  readonly property int launcherWidth: 600
  // Distance from the screen's side edge, the same as the rail's.
  readonly property int edgeGap: 12
}
