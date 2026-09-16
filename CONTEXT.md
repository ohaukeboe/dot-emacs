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

### Emacs / Claude Code

**Claude instance**:
One running Claude Code process together with its terminal buffer, bound to
a project. A project may run several at once; each has an optional name.
_Avoid_: Claude frame, Claude session (upstream's internal struct name)

**Claude side window**:
The dedicated side window (right edge by default) that shows one Claude
instance. The default place an instance is displayed.
_Avoid_: Claude frame, Claude popup

**Claude panel**:
The set of Claude side windows visible in the current tab. Hiding the panel
remembers the set so a project's members can be restored later.

### Binary cache

**attic cache**:
A named namespace on the private binary cache these machines pull from, each
with its own signing key and its own push permission. Three exist —
`homestach`, `folindra`, `simmerly` — one per repository that produces
closures. Public in the sense that pulling needs no token; reachable only from
the tailnet.
_Avoid_: "the cache" unqualified, which reads as cache.nixos.org

**push hook**:
The mechanism that uploads freshly built paths to an **attic cache**. Fires
per build, hands the paths off, and never makes the build wait on the upload.
_Avoid_: "watcher", which names a different upstream mechanism that does not
work here

**pull-only machine**:
A machine configured to fetch from the **attic cache** but not to upload to
it. The work laptop is one: what it builds can involve dependencies fetched
with work credentials, which have no business on a personal cache.

### Dev environments

**Environment kind**:
One of the four things `nix-init` can scaffold for a project: `shell`,
`flake`, `devenv`, `services-flake`. A project has at most one, identified
by its marker file.
_Avoid_: template, which is the file a kind is written from, not the choice

**Loader directive**:
The line in `.envrc` that hands control to nix — `use nix`, `use flake`,
`use devenv`. Each environment kind maps to exactly one. A project has a
single `.envrc`, so the directive is what a second kind collides with.

**Service**:
A long-running process an environment declares (postgres, redis). Started by
a supervisor — `just up`, `devenv up` — never by direnv, which only enters an
environment and exits.
_Avoid_: conflating with the environment that declares it
