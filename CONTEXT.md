# Workstation Config

Personal NixOS + Home Manager configuration for three machines (x13-laptop,
work-laptop, desktop). This glossary pins down terms used when designing
config changes.

## Language

### Audio

**Acoustic Echo Cancellation (AEC)**:
Subtracting the known playback signal (the reference) from the microphone
input so remote parties don't hear the local speakers.
_Avoid_: noise cancellation, noise suppression, mic filtering

**Noise suppression**:
Removing unpredictable background noise (fans, keyboards) from the
microphone. Does not use a reference signal and cannot remove speaker bleed.
_Avoid_: conflating with AEC

**Reference signal**:
The audio an AEC implementation knows is being played, and therefore can
cancel. Only audio routed through the echo-cancel sink becomes reference.

**Echo-cancel pair**:
The virtual sink + virtual source that a PipeWire echo-cancellation setup
creates. Applications play to the virtual sink and record from the virtual
source; the pair wraps the real hardware devices.
