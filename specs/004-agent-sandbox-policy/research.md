# Research: Agent Sandbox Policy

Phase 0 output for [plan.md](./plan.md). Sources are the Claude Code docs
fetched 2026-10-08 (`sandboxing`, `settings-reference`, `permission-modes`,
`permissions`) and checks run on this machine the same day. The wider survey of
isolation options is in the research report
(https://claude.ai/artifact/8D4UEUDdrqXyLTgvFdgapY, revision 3).

Status per item: **verified** (docs quote or run on this machine), or
**validate** (plausible; quickstart probe decides, with a fallback chosen in
advance).

---

## R1. Confinement mechanism

- **Decision**: Use Claude Code's built-in sandbox (`sandbox.enabled = true`).
  Do not wrap the whole `claude` process.
- **Rationale**: The threat model is a cooperative agent acting on its own
  initiative, not evasion. The built-in sandbox covers shell commands. Tools
  outside it (Read/Edit, MCP, hooks) are covered by permission rules and the
  auto mode classifier. It also supplies the approval flow the spec needs (R7)
  and live reload of filesystem lists (R8). A whole-process wrapper would break
  Emacs integration (claude-code-ide launches `claude` inside Emacs), the
  memory-cap session scope, and remote control. It would also need its own
  approval mechanism.
- **Alternatives**: sandbox-runtime, ai-jail, jail.nix/nixpak, microvm.nix.
  All are stronger and all are documented in the report. They are deferred
  until prompt injection enters the threat model. **verified** (docs: "The
  sandbox covers shell commands only").

## R2. Why the previous attempt failed, and Unix sockets

- **Decision**: Set `sandbox.network.allowAllUnixSockets = true` and do not
  install the optional seccomp filter. Hide dangerous sockets by path instead
  (R3).
- **Rationale**: The comment in `workstation/agents/default.nix` records that
  the sandbox broke Nix daemon access and ssh-agent signing. Both are Unix
  sockets. The docs say the seccomp filter "adds Unix domain socket blocking",
  and that on Linux `allowUnixSockets` "is macOS-only. Linux does not support
  per-path Unix socket allowlisting and only supports the all-or-nothing
  `allowAllUnixSockets` approach." The Nix daemon socket is mandatory (FR-007),
  so blocking all sockets is not an option. **verified** (docs).
- **Alternatives**: Proxy the Nix daemon over TCP. Rejected: it adds a
  privileged-ish service for no gain under this threat model.

## R3. Hiding sockets and credential paths

- **Decision**: List credential directories and dangerous sockets as
  `sandbox.credentials.files` entries with `mode = "deny"`.
- **Rationale**: Credential `deny` entries "only ever narrow access, so any
  scope can add one, but no scope can remove one that another scope added",
  which is FR-015. Deny is applied by the filesystem layer, which masks the
  path. A masked socket path should stop `connect()`. The docs do not say so
  for sockets, though, so this is **validate**.
- **Sockets found on this machine** (`ls /run/user/1000`, `id`):
  `/run/docker.sock` (rootful, user in `docker`), `/run/user/1000/docker.sock`
  (rootless), `/run/user/1000/podman/`, `/run/libvirt/` (user in `libvirtd`),
  `/run/user/1000/ssh-agent`, `/run/user/1000/keyring/`,
  `/run/user/1000/1Password-BrowserSupport.sock`, `/run/user/1000/emacs/`,
  `/run/user/1000/bus` (session D-Bus, see R5), `/run/user/1000/gnupg/`
  (when gpg-agent runs).
- **Fallback if masking a socket file does not block it**: for socket
  *directories* (podman, keyring, emacs, gnupg, libvirt) masking the directory
  is enough. For the two loose files, `/run/docker.sock` and
  `/run/user/1000/ssh-agent`: move the main agent socket into a directory
  (`services.ssh-agent.socket = "ssh-agent/socket"`), and drop the user from
  the `docker` group. Rootless Docker is already enabled and stays usable.
- **Non-existent paths** (for example `/run/libvirt` on a machine without
  libvirt): the probe must confirm the session still starts. **validate**.

## R4. Credential path list

- **Decision**: `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.config/gh`,
  `~/.config/sops`, `~/.config/sops-nix` (decrypted sops-nix secrets, which
  include `ssh/main`), `~/.password-store`, `~/.local/share/keyrings`,
  `~/.config/1Password`, `~/.zen`, `~/.mozilla`. The same list also generates
  `permissions.deny` `Read(<path>/**)` rules, because the Read tool runs
  outside the sandbox. Environment variables: `GH_TOKEN`, `GITHUB_TOKEN`.
- **Rationale**: Covers FR-004, FR-005 and FR-009 with one list (constitution
  IV). **verified** that the paths exist (`ls`), and that Read is outside the
  sandbox (docs: "A `denyRead` entry doesn't stop the Read tool").

## R5. process-cap and the session bus

- **Decision**: Hide `/run/user/1000/bus`. Keep
  `/run/user/1000/systemd/private` visible. Change `agent-process-cap`'s
  fail-open check to accept either the bus or the private manager socket.
- **Rationale**: The session bus carries `org.freedesktop.secrets`
  (gnome-keyring, PID 1773 in `busctl --user list`), so exposing it would leak
  keyring secrets through `secret-tool`. `systemd-run --user --scope` talks to
  the user manager over its private socket first. Verified:
  `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent systemd-run --user --scope
  -q --collect -- echo scope-ok` printed `scope-ok`. The helper's current check
  (`[ -z "$bus" ] && [ ! -S "$runtime/bus" ]`) would wrongly fail open once the
  bus is hidden. **verified**.
- **Accepted gap**: Anything that can reach the private socket can also
  `systemctl --user` and `systemd-run --user` a *service*, which runs outside
  the sandbox (spec Assumptions).
- **Alternatives**: `xdg-dbus-proxy` filtering the bus. Rejected for
  complexity.

## R6. Signed commits

- **Decision**: A dedicated ed25519 key `ssh/agent-signing` in
  `sops/home/secrets.yaml`, loaded into a second ssh-agent at
  `%t/ssh-agent-sign` by a user service. Claude Code's `settings.env` sets
  `SSH_AUTH_SOCK` to that socket and overrides `user.signingkey` through
  `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0` and `GIT_CONFIG_VALUE_0`. The key is
  registered on GitHub as a signing key only.
- **Rationale**: Today `user.signingkey` is the inline main key (verified in
  `~/.config/git/config`), and the main agent holds `ssh/main`, `ssh/old` and
  `ssh/trashcan` (verified with `ssh-add -l`). Any process that can sign can
  therefore also push. A separate signing-only identity meets FR-019 and
  FR-020. Git's `GIT_CONFIG_*` environment overrides apply only to processes
  Claude starts, so the user's own commits are unchanged.
- **Alternatives**: Expose the main agent and rely on the `git push` ask rule.
  Rejected: under this threat model the agent could still `ssh` anywhere.
  Keeping the key as a readable file in the sandbox was also rejected, because
  the agent could copy it.
- **validate**: git calls `ssh-keygen -Y sign` with the inline key and gets
  the signature from the agent socket inside the sandbox.

## R7. Agent-proposed policy changes

- **Decision**: Add `permissions.ask` rules for
  `Edit(/.claude/settings.json)` and `Edit(/.claude/settings.local.json)`, set
  `sandbox.allowUnsandboxedCommands = false`, and add guidance in
  `agents-global.md`.
- **Rationale**: Ask rules are in "Actions no mode auto-approves". Without
  them, protected-path writes in auto mode are "Routed to the classifier", not
  to the user. The sandbox's protected paths stop shell commands from writing
  `.claude` settings ("There is no way to exempt one of these paths"). So the
  Edit tool, with its prompt, is the only way to change the policy. Strict mode
  makes Claude Code ignore `dangerouslyDisableSandbox`, and "A `false` in your
  user settings ... holds even when a project's settings set `true`" (FR-003,
  FR-015). **verified** (docs).

## R8. When changes apply

- **Decision**: Rely on live reload for filesystem lists. Document that other
  keys may need a session restart.
- **Rationale**: "When you edit these filesystem lists during a session,
  Claude Code applies the change to the running session, so the next sandboxed
  command runs under the new paths." **verified** for `sandbox.filesystem.*`.
  `permissions.additionalDirectories` and `network.allowedDomains` are
  **validate**. In auto mode, hosts are also named per command for the
  classifier anyway.

## R9. Project policy location

- **Decision**: Use `.claude/settings.local.json` by default. Claude Code adds
  it to the global gitignore. A repo may commit `.claude/settings.json` instead.
  Nix does not generate project policy.
- **Rationale**: The spec requires the agent to be able to propose changes. A
  Nix-generated file would be a read-only store symlink and need a rebuild for
  every change. Scope merging adds project entries to the floor, and the floor's
  denies stay in force (R3, R7). **verified** (docs: "Claude Code merges them,
  combining the paths").

## R10. Nix daemon, builds and KVM

- **Decision**: Do not expose `/dev/kvm` to the agent sandbox, and do not add
  daemon-specific rules.
- **Rationale**: `nix build` asks the daemon to build. The builds, including
  NixOS VM tests such as `packages.test-disk-layout`, run in the daemon's own
  sandbox, which has KVM through `system-features`. They do not run inside the
  agent's bubblewrap. Only running a VM directly from the agent's shell (for
  example `./result/bin/run-*-vm` after `build-vm`) needs `/dev/kvm` there.
  That case is a project exception (an `excludedCommands` pattern), and the
  quickstart checks whether `/dev/kvm` is present. `trusted-users = root` only
  is verified in `/etc/nix/nix.conf`, so the daemon is not a way to become
  root. Flake inputs are fetched by the Nix client through the proxy, so the
  baseline allowlist includes the GitHub fetch hosts. **verified** (daemon and
  trusted-users); KVM presence **validate**.

## R11. Fail closed and dependencies

- **Decision**: `sandbox.failIfUnavailable = true`. Put `pkgs.bubblewrap` and
  `pkgs.socat` on the Home Manager `home.packages` path.
- **Rationale**: "By default, if the sandbox can't start because a dependency
  is missing ... Claude Code runs commands without sandboxing." On NixOS
  nothing guarantees `bwrap` is on `PATH`. User namespaces are on by default in
  NixOS. FR-002 and SC-008. **verified** (docs).

## R12. Pushing

- **Decision**: No push credentials in the baseline. Keep `git push` in
  `agents.sensitiveBashPrefixes` (already there), so a project that grants
  credentials still gets a prompt (FR-022).
- **Rationale**: Ask rules prompt "even for sandboxed commands" in auto-allow
  mode. **verified** (docs).

## R13. Open SSH connections

- **Decision**: Change `ControlPath` from `/tmp/ssh-%u-%r@%h:%p` to
  `~/.ssh/cm-%C`, which falls under the `~/.ssh` deny.
- **Rationale**: With `ControlPersist = 10m`, an open master connection in
  `/tmp` can be reused by any process that sees `/tmp` (FR-021). `%C` hashes
  the connection tuple, which keeps the path short. **verified** (the current
  value in `workstation/ssh.nix`).

## R14. Leftover placeholder files

- **Decision**: Document `claude doctor` in the quickstart and in
  `agents-global.md` troubleshooting.
- **Rationale**: Docs: a killed session leaves 0-byte read-only placeholders at
  `.claude` settings paths, and saving a permission then fails. process-cap's
  SIGKILL makes this more likely. **verified** (docs).

## R15. `~/.cache/nix` must be writable (found during implementation)

- **Decision**: Add the `agents.sandbox.writablePaths` option, defaulting to
  `[ "~/.cache/nix" ]` and rendered as `sandbox.filesystem.allowWrite`.
- **Rationale**: Running the probe under a bwrap with a read-only `$HOME`,
  `nix build nixpkgs#hello` failed with `error: creating symlink
  "/home/oskar/.cache/nix/flake-registry.json.tmp-…": Read-only file system`.
  The Nix client writes its flake registry, fetcher cache and eval cache there.
  Without the entry, every flake command breaks inside the sandbox.
  **verified**.

## R3 addendum: socket masking (2026-10-08)

Under bwrap, binding `/dev/null` over a socket file (`/run/docker.sock`,
`/run/user/1000/bus`) and a tmpfs over a socket directory
(`/run/user/1000/emacs`) both made `socat UNIX-CONNECT` fail. If Claude Code's
`credentials.files` deny masks paths the same way, socket hiding holds. The
final check is still the probe inside the real session (T017). **partly
verified**.

## R16. `excludedCommands` and the rewriter chain (open)

- **Risk**: The process-cap stage rewrites every command into
  `agent-process-cap run fg <base64>` (ADR 0003). If Claude Code matches
  `sandbox.excludedCommands` against the rewritten text, an entry like
  `docker compose *` never matches, and project exemptions silently do nothing.
- **Status**: **validate** during T028 by adding a harmless exclusion (for
  example `"id *"`) in a scratch project. Check whether `id -u` still runs
  sandboxed: the `/sandbox` Config tab or a write to `$HOME` shows it.
- **Fallback if it fails**: The process-cap stage skips commands matching the
  project's `excludedCommands`. Or project policy uses the existing `nocap `
  token together with the exclusion. Recorded here so US3's reference profiles
  are not trusted before it is checked.

## R5 correction (2026-10-09): process cap inside the sandbox

R5's verification was wrong. With `DBUS_SESSION_BUS_ADDRESS` pointed at a dead
path, `systemd-run` still succeeded, but only because the real bus socket was
there. Findings inside the deployed sandbox:

- With the bus hidden, every capped command failed:
  `Failed to connect to user scope bus via local transport: No data available`.
- `systemd-run --user` (systemd 261.3) only connects through
  `$XDG_RUNTIME_DIR/systemd/private`. With that path absent it fails with
  `No such file or directory` and never tries `DBUS_SESSION_BUS_ADDRESS`. A
  filtered bus proxy (`xdg-dbus-proxy`, tried and removed) therefore cannot
  help, even though `busctl --user status` worked through it.
- The private socket rejects sandboxed callers during authentication
  (`AUTHENTICATING → CLOSED`). The sandbox runs each command in its own PID
  namespace with `uid_map` `1000 0 1`.
- The sandbox's own `bwrap` command line (`/proc/1/cmdline`) includes
  `--die-with-parent` and a private PID namespace. Nothing a command starts can
  outlive it, which already closes dot-emacs-k6c's failure mode.

**Decision**: When `SANDBOX_RUNTIME=1`, `agent-process-cap` runs
`timeout --kill-after=<grace> <cap> bash -c`, mapping 124 to 143. The
per-command memory scope is lost; the session scope still bounds the sandbox.
Probe A05 checks the sandbox branch and `timeout`. Side effect: a daemon
started with `nocap` inside the sandbox dies when its command returns.

## R17. Masked `.gitmodules` breaks flake evaluation (open)

The sandbox masks a non-existent `.gitmodules` in the working directory with a
`/dev/null` character device (a protected path). Nix's libgit2 then fails on
every git-backed flake:
`error: parsing .gitmodules file: failed open - '…/.gitmodules' is locked:
Permission denied (libgit2 error code = 2)`. `nix flake check`, `nix build .#…`,
`nix eval .#…` and `nix fmt` all fail in the sandbox. Masked paths cannot be
exempted by settings. Options: `path:` flake references (include untracked
files), a project `excludedCommands` entry (unsandboxed, and possibly never
matched because of the rewriter chain, R16), or creating an empty `.gitmodules`
(changes the repo). Awaiting a decision.

## R18. Sandbox owns `GIT_CONFIG_COUNT` (affects R6)

The sandbox sets `GIT_CONFIG_COUNT=2` with `GIT_CONFIG_KEY_0/1 =
safe.directory`, which overwrites a `settings.env` `GIT_CONFIG_COUNT` override.
The signing key override uses `GIT_CONFIG_PARAMETERS` instead:
`'user.signingkey'='key::<pubkey>'`. It applies alongside the sandbox's
entries. **validate** at T025.

## R16 update (2026-10-09): confirmed, fixed in the chain

After a restart, `nix eval .#…` with `"nix eval *"` in the project's
`excludedCommands` still ran sandboxed. Because the restart ruled out a reload
problem, Claude Code must be matching the rewritten text. **Decision**: the
rewriter chain passes plain calls that match an exclusion through unchanged
(ADR 0003 amendment). The matcher was tested: bypass for `nix build`, `nix eval
--raw .#x` and quoted attribute paths; capped for `| tail`, `cd x && …`,
`$(…)` and non-matching `nix run`.

## R17 update: `path:` refs fail too

`nix flake check path:.` fails with `file '…/.bash_profile' has an unsupported
type`. The sandbox masks missing shell rc files in the working directory with
`/dev/null` devices, and the path fetcher rejects character devices. Decision
for this repo: project `excludedCommands` for `nix flake check`, `nix build`,
`nix eval` and `nix fmt` (user choice, 2026-10-09).
