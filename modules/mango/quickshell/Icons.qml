pragma Singleton
pragma ComponentBehavior: Bound

// Nerd Font (Material Design) glyphs, by name. Codepoints checked against
// nerd-fonts.symbols-only 3.5.0.
import Quickshell
import Quickshell.Services.UPower

Singleton {
  readonly property string volume: String.fromCodePoint(0xF057E)
  readonly property string volumeOff: String.fromCodePoint(0xF075F)
  readonly property string brightness: String.fromCodePoint(0xF00DF)
  readonly property string wifi: String.fromCodePoint(0xF0928)
  readonly property string wifiOff: String.fromCodePoint(0xF092D)
  readonly property string bluetooth: String.fromCodePoint(0xF00AF)
  readonly property string bluetoothOff: String.fromCodePoint(0xF00B2)
  readonly property string mic: String.fromCodePoint(0xF036C)
  readonly property string micOff: String.fromCodePoint(0xF036D)
  readonly property string lock: String.fromCodePoint(0xF033E)
  readonly property string account: String.fromCodePoint(0xF0004)
  readonly property string power: String.fromCodePoint(0xF0425)
  readonly property string logout: String.fromCodePoint(0xF0343)
  readonly property string sleep: String.fromCodePoint(0xF04B2)
  readonly property string restart: String.fromCodePoint(0xF0709)
  // Picker tiles whose icon name is missing or unknown.
  readonly property string generic: String.fromCodePoint(0xF0766)
  readonly property string plug: String.fromCodePoint(0xF06A5)
  readonly property string chevronRight: String.fromCodePoint(0xF0142)
  readonly property string chevronLeft: String.fromCodePoint(0xF0141)
  readonly property string refresh: String.fromCodePoint(0xF0450)
  readonly property string terminal: String.fromCodePoint(0xF018D)
  readonly property string asterisk: String.fromCodePoint(0xF06C4)
  readonly property string phone: String.fromCodePoint(0xF011C)
  readonly property string tablet: String.fromCodePoint(0xF04F6)
  readonly property string ring: String.fromCodePoint(0xF009E)
  readonly property string upload: String.fromCodePoint(0xF0552)
  readonly property string clipboard: String.fromCodePoint(0xF014C)
  readonly property string search: String.fromCodePoint(0xF0349)
  readonly property string folder: String.fromCodePoint(0xF024B)
  readonly property string message: String.fromCodePoint(0xF0361)
  readonly property string plus: String.fromCodePoint(0xF0415)
  readonly property string close: String.fromCodePoint(0xF0156)
  readonly property string bell: String.fromCodePoint(0xF009A)
  readonly property string keyboard: String.fromCodePoint(0xF030C)

  // Rail status icons, the sets waybar's format-icons used.
  readonly property var wifiLevels: [0xF091F, 0xF0922, 0xF0925, 0xF0928].map(c => String.fromCodePoint(c))
  readonly property string ethernet: String.fromCodePoint(0xF0200)
  readonly property string offline: String.fromCodePoint(0xF092E)
  readonly property var volumeLevels: [0xF057F, 0xF0580, 0xF057E].map(c => String.fromCodePoint(c))
  readonly property var batteryLevels: [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079].map(c => String.fromCodePoint(c))
  // The charging twin of each batteryLevels step.
  readonly property var chargingLevels: [0xF089F, 0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085].map(c => String.fromCodePoint(c))

  // The level glyph for a 0..1 fraction, in even steps as waybar picks them.
  function level(list, fraction) {
    const i = Math.floor(Math.max(0, Math.min(1, fraction)) * list.length);
    return list[Math.min(list.length - 1, i)];
  }

  // A UPower device's glyph: its level, charging twin, or a plug when it
  // sits on the charger without charging.
  function battery(device) {
    if (device.state === UPowerDeviceState.Charging) return level(chargingLevels, device.percentage);
    if (device.state === UPowerDeviceState.FullyCharged
        || device.state === UPowerDeviceState.PendingCharge) return plug;
    return level(batteryLevels, device.percentage);
  }
}
