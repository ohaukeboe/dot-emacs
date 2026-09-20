# Workstation Config

Personal NixOS + Home Manager configuration for three machines (x13-laptop,
work-laptop, desktop). This glossary pins down terms used when designing
config changes. Keep terms short and link decisions to the relevant ADR under
`docs/adr/`.

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

### Emacs / beads

**Bead**:
One issue in the beads tracker, identified by `dot-emacs-<suffix>`. Lives in
`.beads/` beside the worktree, so it belongs to a repository the way a branch
does.
_Avoid_: ticket; task, which is one of bd's `issue_type` values and so already
means something narrower

**Ready**:
Open and unblocked: every dependency of the bead is closed, so it can be
claimed now. Computed by `bd`, never derived in Emacs — a second
implementation of blocker resolution would drift from the first.
_Avoid_: open, which includes blocked beads

**In progress**:
Claimed, by a person or by an agent. The assignee says who holds it, not
whether it is yours; a bead an agent is working on is in progress.

**Beads section**:
The Magit status section listing the in-progress and ready beads of the
repository at `magit-toplevel`. Absent when the repository has no `.beads/`,
and when both lists are empty.

### Emacs / windows

**Side-by-side split**:
Dividing a window into windows placed left and right of each other.
_Avoid_: horizontal split, vertical split (Emacs uses both for this)

**Stacked split**:
Dividing a window into windows placed above and below each other.
_Avoid_: horizontal split, vertical split

**Row**:
A group of windows that share one side-by-side split. Windows in a row
are kept at equal width.
_Avoid_: combination, column

**Automatic split**:
A split Emacs chooses on its own to show a buffer, as opposed to one the
user asks for with a split command. Automatic splits are always
side-by-side and never make windows narrower than a set minimum.
_Avoid_: pop-up window

### Emacs / projects

**Project**:
A git repository that project.el remembers. Created in Emacs by either
cloning or creating a new one; both land directly under a project parent
directory.
_Avoid_: repo (when the project.el registration matters), projection
project, flake

**Project parent directory**:
A directory whose immediate children are projects. project.el scans each one
at startup, and it is where new and cloned projects are placed. Any path can
be chosen at the prompt, but only the configured ones are scanned.
_Avoid_: workspace, projects root

### Binary cache

**attic cache**:
A named namespace on the private binary cache these machines pull from, each
with its own signing key and its own push permission. These machines use one,
`homestach`, for both directions: they pull from it and the ones that are not
work machines push to it, alongside the homestach repo's own closures. Other
projects have namespaces on the same server; they are not listed here, because
a namespace nothing on these machines pulls from is only a substituter to time
out on. A namespace is not free — it needs a key and a token issued on the
server, in the homestach repo — which is why this repo has none of its own.
`modules.attic.cacheName` is where that choice is written. Public in the sense
that pulling needs no token; reachable only from the tailnet.
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

**Secrets backend**:
Where a project's secrets live and which tool reads them: `sops`, `dotenv`,
or `secretspec`. Chosen independently of the environment kind, so any kind
can carry any backend, and a project may have none.
_Avoid_: provider, which is secretspec's word for the 33 stores it can read;
the secretspec backend uses the sops provider, and those are two levels

**Backend marker**:
The file whose presence means a project already has a secrets backend —
`secretspec.toml`, `.sops.yaml`, `.env`. The counterpart to an environment
kind's marker, and what a second backend collides with.

**Load-time secret**:
A secret direnv exports on entering the directory, so every process under
that root inherits it — including, under `envrc.el`, everything Emacs spawns
there. Only the dotenv backend works this way.
_Avoid_: treating the blast radius as terminal-only; it is not

**Explicit-run secret**:
A secret that reaches only the one child process asked for it, via
`sops exec-env` or `secretspec run`. The sops and secretspec backends work
this way.

### Provisioning

**Installer entrypoint**:
The single command run from a booted NixOS installer that takes a machine
from "no repo" to "installed": it fetches this repo and walks through every
provisioning step in order. Safe to re-run; it resumes where it stopped. It
can also reinstall a machine that is already registered. Firmware
preparation is outside it.
_Avoid_: bootstrap, which already names the host-key + git-agecrypt step
that the entrypoint runs as one of its stages

**Bootstrap**:
Installing the shared host age key and unlocking the encrypted private files
in a checkout. The first thing any fresh checkout needs, installer or not.
_Avoid_: using it for the whole install

**Registered machine**:
A machine with an entry in the machine registry, and so a NixOS
configuration to install or rebuild. Only a registered machine with a
declarative disk layout can be (re)installed by the installer entrypoint.

### Sleep / hibernation

See ADR 0001.

**suspend-then-hibernate**:
systemd sleep mode: suspend to RAM first, then automatically hibernate after
`HibernateDelaySec`, or on critical battery.

**hibernate (S4)**:
Write RAM contents to disk swap and power off; restore on next boot.

**suspend (S3)**:
Keep RAM powered, everything else off. Fast resume, but drains battery and
loses state if power is lost.

**swapfile**:
A regular file used as swap space; here it is the hibernation-image target.
Created declaratively via `swapDevices.*.size`.

**zswap**:
Kernel compressed _cache_ in front of a real disk swap device; pages fall
through to the swapfile when the pool is full. Configured via `zswap.*`
kernel parameters.
_Avoid_: conflating with zram

**zram**:
A compressed _block device_ used directly as swap, backed by RAM. Disabled on
machines using suspend-then-hibernate, to avoid overlapping with zswap.
_Avoid_: conflating with zswap

**resume_offset / HibernateLocation**:
The block offset of the hibernation image within the swapfile. With systemd
in initrd, recorded automatically in the `HibernateLocation` EFI variable
instead of a static kernel parameter.

**NoCOW (`chattr +C`)**:
btrfs attribute disabling copy-on-write; required for swapfiles on btrfs.
NixOS sets it automatically when creating a swapfile via `swapDevices.*.size`.
