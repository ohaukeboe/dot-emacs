# System-wide Acoustic Echo Cancellation on NixOS + PipeWire

Research report. Question: remove **all** speaker output from the microphone
signal so speakers can be used during online calls, declaratively, on all three
hosts, surviving device swaps.

Verified against the live system: **PipeWire 1.6.5** (`pw-cli --version`),
`libpipewire-module-echo-cancel.so` present, NixOS option
`services.pipewire.extraConfig.pipewire` confirmed (generates drop-ins under
`/etc/pipewire/pipewire.conf.d/`).

## TL;DR

Use PipeWire's native `libpipewire-module-echo-cancel` with the WebRTC backend
and **`monitor.mode = true`**. This taps the monitor of whatever the current
default sink is as the cancellation reference, so **all** playback is cancelled
without forcing apps through a virtual sink, and it follows the default sink
when you swap devices. Select the resulting "Echo Cancellation Source" as your
mic. Config goes in the existing `services.pipewire` block in
`common/system/system.nix`.

## How the module works (verified)

`libpipewire-module-echo-cancel` creates four linked streams
([PipeWire docs](https://docs.pipewire.org/page_module_echo_cancel.html),
[Arch manpage](https://man.archlinux.org/man/libpipewire-module-echo-cancel.7.en)):

| Stream | Role |
|---|---|
| **capture** | reads the real microphone |
| **sink** (virtual) | receives the audio to be cancelled = the *reference* |
| **playback** | forwards the sink audio to the real speakers |
| **source** (virtual) | exposes the echo-cancelled mic to apps |

AEC works by correlating the reference (sink) with the mic capture and
subtracting it. **Consequence: only audio that reaches the reference gets
cancelled.** Two ways to make *all* playback the reference:

- **Topology A — virtual sink as default.** Make "Echo Cancellation Sink" the
  system default sink; every app plays through it, so everything is reference.
  This is the literal "echo-cancel sink as default" idea. Downside: the default
  device is now a virtual node; the module's `playback` stream must track the
  *real* output device on swaps, which is the fragile path historically.
- **Topology B — `monitor.mode = true` (recommended).** Instead of a virtual
  playback sink, the module captures the **monitor ports of the current default
  sink** as the reference. All output on the real default sink is cancelled
  *without changing the default sink*. It naturally follows the default sink
  when you swap devices, and only a virtual **source** is created (apps keep
  using the normal sink, just pick the echo-cancel source as mic). This fits all
  four constraints — system-wide, all-playback, declarative, device-swap —
  better than A.

Default backend is WebRTC (`library.name = aec/libspa-aec-webrtc`), tunable via
`aec.args`.

## Device-swap behaviour

- Omit `capture.props`/`sink.props` `node.target` → the module follows the
  **fallback (default) source and sink**
  ([Arch examples](https://wiki.archlinux.org/title/PipeWire/Examples)). With
  `monitor.mode` this means the reference re-points at whatever sink is default,
  including Bluetooth headsets and the headphone jack.
- **Harmless with headphones:** when headphones are the default sink there is no
  acoustic echo path; the adaptive WebRTC filter converges to ≈0 subtraction, so
  the mic is effectively passthrough. (See risk below.)

## Alternatives considered

- **`filter-chain` module** — builds arbitrary LADSPA/LV2/builtin graphs and can
  be a virtual sink/source, but its builtin set has no AEC block; you'd be
  reimplementing what echo-cancel already does. Not worth it here.
- **EasyEffects** — GUI/Home-Manager effects host, good for noise suppression
  (RNNoise) and EQ, but it is a per-user app-level processor, not the
  system-wide PipeWire-graph AEC the question requires. Complementary, not a
  replacement. (Can stack RNNoise noise-suppression *after* AEC later.)

## Performance / tradeoffs

- WebRTC AEC adds a small constant processing latency and light CPU on the mic
  path; `monitor.mode` avoids the extra resample/route of pushing *all* playback
  through a virtual sink (Topology A), so it's the lighter option.
- **PipeWire 1.4.7** (2025-10) improved echo-cancel latency handling / fixed
  incorrect latency reporting
  ([Linuxiac](https://linuxiac.com/pipewire-1-4-7-released-with-echo-cancellation-and-latency-fixes/)).
  System is on 1.6.5 → includes this.

## Deploy gotcha (IMPORTANT)

PipeWire runs as a **user** service. `sudo nixos-rebuild switch` writes the new
`/etc/pipewire/pipewire.conf.d/` drop-in but does **not** restart the running
per-user daemon, so the module never loads and the "Echo Cancellation Source"
does not appear. After every deploy that touches PipeWire config:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

(or log out / reboot). Verify with `pactl list sources short | grep echo-cancel`.
The virtual source shows in `wpctl status` under **Filters**, not **Sources**
(it has no backing device), but apps see it as a normal mic via the pulse layer.

## Config key note

Use `library.name = "aec/libspa-aec-webrtc"`, **not** `aec.method = "webrtc"`.
On PipeWire 1.6.5 the latter logs `aec.method is not supported anymore use
library.name` and falls back to the webrtc default (so it still works, but the
key is deprecated/removed).

## Known issues

- **Old `capture.props`/`playback.props` ignored bug** (#2939) affected
  PipeWire ≤ 0.3.63, fixed in 0.3.64. **Irrelevant at 1.6.5.**
- **Bluetooth audio-loss report (unverified, single source):** an Arch BBS
  thread reports echo-cancel with `monitor.mode` intermittently killing output
  to a Sony WH-1000XM5 until the fallback checkbox is toggled
  ([BBS 301896](https://bbs.archlinux.org/viewtopic.php?id=301896)). Could not
  confirm reproducibility or version. **Risk to watch** on the laptops' BT
  headsets; mitigation if it bites: restrict the module to non-BT sinks or
  disable per-host.
- The **NixOS Wiki PipeWire page has no AEC coverage** — no canonical Nix
  example exists; config below is adapted from upstream + Arch examples into the
  `extraConfig.pipewire` schema.

## Recommended config

See the implemented module in `common/system/system.nix` (the
`60-echo-cancel` drop-in). To switch to Topology A instead, drop `monitor.mode`
and set the Echo Cancellation Sink as the default sink via a WirePlumber rule.

## Sources

- PipeWire docs — module-echo-cancel: https://docs.pipewire.org/page_module_echo_cancel.html
- Arch manpage — libpipewire-module-echo-cancel: https://man.archlinux.org/man/libpipewire-module-echo-cancel.7.en
- Arch wiki — PipeWire/Examples (monitor.mode, node.target): https://wiki.archlinux.org/title/PipeWire/Examples
- PipeWire filter-chain: https://docs.pipewire.org/page_module_filter_chain.html
- PipeWire 1.4.7 latency fixes: https://linuxiac.com/pipewire-1-4-7-released-with-echo-cancellation-and-latency-fixes/
- Bug #2939 (fixed 0.3.64): https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/2939
- BT audio-loss report: https://bbs.archlinux.org/viewtopic.php?id=301896
