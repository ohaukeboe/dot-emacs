---

description: "Task list for Agent Sandbox Policy"
---

# Tasks: Agent Sandbox Policy

**Input**: Design documents from `/specs/004-agent-sandbox-policy/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: No unit tests requested. The runtime check is `agent-sandbox-probe`
(FR-025, [contracts/probe-cli.md](./contracts/probe-cli.md)), built as part of
US1 and extended per story. Evaluation-level checks are the assertions A1 to A5
in [contracts/nix-options.md](./contracts/nix-options.md).

**Organization**: Tasks are grouped by user story so each story can be
implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1 to US4)

## Path Conventions

Single-repo NixOS/Home Manager configuration. All paths are relative to the
repository root. After creating any new file, run `git add <file>` before
`nix build` or `nix flake check`, because the flake only sees tracked files.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Record the decision and the vocabulary before code lands (constitution IV).

- [X] T001 [P] Write ADR `docs/adr/0004-agent-sandbox-policy.md` in the format of `docs/adr/0003-agent-bash-rewriter-chain.md`. Cover: the threat model (a cooperative agent acting on its own initiative; prompt injection out of scope); the decision to use Claude Code's built-in sandbox, not a whole-process wrapper (research R1); `allowAllUnixSockets` plus path masking (R2, R3); and that it supersedes the "Keep the Claude Code sandbox off" comment in `workstation/agents/default.nix`. Link the report URL from research.md.
- [X] T002 [P] Add terms under the "Agents" section of `CONTEXT.md`: **sandbox baseline** (Nix-generated user-scope policy, not writable by the agent), **project policy** (`.claude/settings.local.json` or `.claude/settings.json` additions), **policy proposal** (an agent Edit to a project policy, always prompted), **agent signing key** (`ssh/agent-signing`, signing-only, separate ssh-agent).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Module skeleton, options and dependencies that every story builds on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 Create `workstation/agents/sandbox.nix` with `options.agents.sandbox` exactly as in `contracts/nix-options.md`. Types: `runtimeDir` is `strMatching "^/run/user/[0-9]+$"` with default `"/run/user/1000"`. `credentialPaths` is `listOf (strMatching "^(~/|/).+")`. `hiddenSockets` is `listOf (strMatching "^/.+")`. `deniedEnvVars` is `listOf (strMatching "^[A-Z_][A-Z0-9_]*$")`. `signing.publicKey` is `strMatching "^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$"`. `signing.socketName` is `strMatching "^[A-Za-z0-9._-]+$"` with default `"ssh-agent-sign"`. `signing.secret` defaults to `"ssh/agent-signing"`. Set `signing.enable` to default `false` for now; T024 flips it. Put the whole `config` under `lib.mkIf cfg.enable`. Never use the literal username: use `~/` paths or `config.home.homeDirectory`.
- [X] T004 Import `./sandbox.nix` in the `imports` list of `workstation/agents/default.nix`. Delete the `programs.claude-code.settings.sandbox.enabled = false;` line and its comment. In `sandbox.nix`, set `programs.claude-code.settings.sandbox.enabled = lib.mkDefault false` outside the `mkIf`, so a disabled module still yields `false` (constitution V).
- [X] T005 [P] In `workstation/agents/sandbox.nix`, add `pkgs.bubblewrap` and `pkgs.socat` to `home.packages` under `mkIf cfg.enable` (research R11).
- [X] T006 [P] Fix the fail-open check in the `agent-process-cap` helper in `workstation/agents/process-cap.nix`. Fail open only when `systemd-run` is missing, or when *none* of `$DBUS_SESSION_BUS_ADDRESS`, `$XDG_RUNTIME_DIR/bus` or `$XDG_RUNTIME_DIR/systemd/private` is available. Add a comment citing research R5: the session bus is hidden by the sandbox, and `systemd-run --user` reaches the manager over the private socket.
- [X] T007 `git add workstation/agents/sandbox.nix`. Run `nix fmt` and revert unrelated churn. Run `nix flake check` and `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`. Both must pass with the module enabled but nothing rendered yet.

**Checkpoint**: The module exists, evaluates and renders nothing. process-cap works with or without the bus.

---

## Phase 3: User Story 1 - Auto mode cannot touch credentials or the system (Priority: P1) 🎯 MVP

**Goal**: Every shell command the agent runs is confined. Credentials and the services that act with your authority are invisible. System changes are refused. Nix, builds and journal reads still work.

**Independent Test**: Ask the agent to run `agent-sandbox-probe` in a project with no policy. All `B*`, `S*`, `E*`, `W*`, `N01` rows fail as expected, and `A01`, `A02`, `A05`, `A07` succeed (quickstart scenario 1). Then do quickstart scenario 2 (fail closed).

- [X] T008 [US1] Set the `credentialPaths` default in `workstation/agents/sandbox.nix` to research R4's list: `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.config/gh`, `~/.config/sops`, `~/.config/sops-nix`, `~/.password-store`, `~/.local/share/keyrings`, `~/.config/1Password`, `~/.zen`, `~/.mozilla`.
- [X] T009 [US1] Set the `hiddenSockets` default in `workstation/agents/sandbox.nix`, built from `cfg.runtimeDir`: `/run/docker.sock`, `${runtimeDir}/docker.sock`, `${runtimeDir}/podman`, `/run/libvirt`, `${runtimeDir}/gnupg`, `${runtimeDir}/keyring`, `${runtimeDir}/emacs`, `${runtimeDir}/1Password-BrowserSupport.sock`, `${runtimeDir}/bus`. Add `${runtimeDir}/ssh-agent` only when `cfg.signing.enable`. Hiding the main agent before the signing agent exists would break commit signing, the failure that disabled the sandbox before.
- [X] T010 [US1] Render the sandbox block in `workstation/agents/sandbox.nix` under `mkIf cfg.enable`: `programs.claude-code.settings.sandbox = { enabled = true; failIfUnavailable = true; allowUnsandboxedCommands = false; network.allowAllUnixSockets = true; network.allowedDomains = cfg.allowedDomains; credentials.files = map (path: { inherit path; mode = "deny"; }) (cfg.credentialPaths ++ cfg.hiddenSockets); credentials.envVars = map (name: { inherit name; mode = "deny"; }) cfg.deniedEnvVars; }`. Set `allowedDomains` to default to `cache.nixos.org`, `channels.nixos.org`, `github.com`, `codeload.github.com`, `api.github.com`, `objects.githubusercontent.com`.
- [X] T011 [US1] Render the permission rules in `workstation/agents/sandbox.nix`: `programs.claude-code.settings.permissions.deny = map (p: "Read(${p}/**)") cfg.credentialPaths ++ map (c: "Bash(${c}:*)") cfg.deniedCommands`, with `deniedCommands` defaulting to `[ "sudo" "nixos-rebuild switch" "nixos-rebuild boot" "nixos-rebuild test" ]`. Check that Home Manager merges this list with any other `permissions.deny` contributors instead of overriding them.
- [X] T012 [US1] Add assertions A1, A2 and A5 from `contracts/nix-options.md` to `workstation/agents/sandbox.nix`.
  - A1: no `hiddenSockets` entry is equal to, or a prefix of, `/nix/var/nix/daemon-socket`, `${runtimeDir}/systemd` or `${runtimeDir}/${signing.socketName}`.
  - A2: `config.agents.processCap.enable` implies `"${runtimeDir}/bus"` is in `hiddenSockets`.
  - A5: `config.programs.ssh.settings."*".ControlPath or ""` does not start with `/tmp`.
  - Each message names the file, the offending value and the FR it protects.
- [X] T013 [US1] Change `ControlPath` in `workstation/ssh.nix` from `"/tmp/ssh-%u-%r@%h:%p"` to `"~/.ssh/cm-%C"`, with a comment citing FR-021 and research R13. It is needed now because A5 would fail otherwise.
- [X] T014 [US1] Create the probe in `workstation/agents/sandbox.nix` as `pkgs.writeShellApplication { name = "agent-sandbox-probe"; runtimeInputs = [ coreutils curl socat nix openssh systemd findutils jq ]; }` per `contracts/probe-cli.md`.
  - Generate `B*` rows from `cfg.credentialPaths`, `S*` rows from `cfg.hiddenSockets`, and `E*` rows from `cfg.deniedEnvVars`.
  - For directories, `S*` probes every socket found with `find <dir> -type s`. A missing or unlistable directory counts as `ok`.
  - Add the fixed rows `W01` to `W03`, `N01`, `A01`, `A02`, `A05`, `A07` and `I01`.
  - Start with the not-in-sandbox guard: exit 2 if writing `$HOME/.agent-sandbox-probe` succeeds, after removing the file.
  - Never print file contents. A successful read is reported as `LEAK: <path>`.
  - Support `--json`.
  - Expand `~` to `$HOME` at runtime, not at evaluation time.
  - Add it to `home.packages` under `mkIf cfg.enable`.
- [X] T015 [US1] Add a `## Sandbox` section to `workstation/agents/agents-global.md`:
  - What to do on a sandbox failure: steps 1 to 4 of `contracts/project-policy.md` "Agent behaviour on a sandbox failure".
  - Never work around a block.
  - Baseline credentials and hidden services cannot be lifted by project policy.
  - Run `agent-sandbox-probe` when asked to verify the sandbox.
  - `claude doctor` for leftover 0-byte placeholder files (research R14).
- [X] T016 [US1] `git add` the changed files. Run `nix fmt`, `nix flake check` and the Home Manager build from T007. Then break each new assertion on purpose and confirm evaluation fails with its message: add `"/nix/var/nix/daemon-socket"` to `hiddenSockets` (A1), drop `${runtimeDir}/bus` (A2), and set ControlPath back to `/tmp/...` (A5). Revert each one.
- [X] T017 [US1] Deploy with `sudo nixos-rebuild switch --flake .#<hostname>` (the user runs this), then restart Claude Code. Do quickstart scenario 1: the agent runs `agent-sandbox-probe`, and every row is `ok`. If an `S*` row reports a reachable socket, apply research R3's fallback and record which one in `research.md` R3. For a loose file, move it into a directory. For `/run/docker.sock`, remove `"docker"` from `extraGroups` in `common/system/system.nix`. Do quickstart scenario 2 (fail closed). Record whether `I01` reports `/dev/kvm`.

**Checkpoint**: US1 is fully functional. The sandbox is on, Nix works, and signing still uses the main agent, which is not yet hidden because `signing.enable = false`.

---

## Phase 4: User Story 2 - Signed commits, no push (Priority: P2)

**Goal**: The agent signs commits with a signing-only key from its own ssh-agent. The main agent is hidden. Pushes fail.

**Independent Test**: Quickstart scenario 3. Probe rows `A03`, `A04` and `P01` are `ok`. `git log --show-signature -1` shows the agent key. Your own terminal commits still use the main key.

- [ ] T018 [US2] Manual step for the user, not the agent: generate the key with `ssh-keygen -t ed25519 -N '' -C claude-agent -f /tmp/agent-signing`, add the private key to `sops/home/secrets.yaml` as `ssh/agent-signing` using `sops`, shred the temporary files, and register the public key on GitHub as a **Signing Key** only. The agent pauses here and asks the user to do it, because the agent must never see the private key.
- [X] T019 [P] [US2] Declare `"ssh/agent-signing" = { };` next to `"ssh/main"` in `workstation/sops.nix`.
- [X] T020 [P] [US2] Add `systemd.user.services.ssh-agent-sign` to `workstation/ssh.nix`, guarded by `lib.mkIf (isLinux && config.agents.sandbox.enable && config.agents.sandbox.signing.enable)`.
  - Order it with `Unit.After`/`Wants = [ "sops-nix.service" ]`, and set `Install.WantedBy = [ "default.target" ]`.
  - `Service.ExecStart`: `${lib.getExe' pkgs.openssh "ssh-agent"} -D -a %t/${config.agents.sandbox.signing.socketName}`.
  - `Service.ExecStartPost`: a `writeShellApplication` that waits for the socket, then runs `ssh-add ${config.sops.secrets."ssh/agent-signing".path}` with `SSH_AUTH_SOCK` set to that socket.
  - Include a comment citing research R6.
- [X] T021 [US2] Render the signing environment in `workstation/agents/sandbox.nix` under `mkIf (cfg.enable && cfg.signing.enable)`: `programs.claude-code.settings.env = { SSH_AUTH_SOCK = "${cfg.runtimeDir}/${cfg.signing.socketName}"; GIT_CONFIG_COUNT = "1"; GIT_CONFIG_KEY_0 = "user.signingkey"; GIT_CONFIG_VALUE_0 = "key::${cfg.signing.publicKey}"; }`. It must merge with the existing `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.
- [X] T022 [US2] Add assertions A3 and A4 to `workstation/agents/sandbox.nix`. A3: `signing.enable` implies `signing.publicKey` is set and `config.sops.secrets ? ${cfg.signing.secret}`. A4: `signing.enable` implies `"~/.ssh"` is in `credentialPaths`.
- [X] T023 [US2] Add probe rows `A03`, `A04` and `P01` to `agent-sandbox-probe` in `workstation/agents/sandbox.nix`, under `cfg.signing.enable`:
  - `A03`: `ssh-add -l` lists exactly one key, whose fingerprint matches `cfg.signing.publicKey`. Compute it at runtime with `ssh-keygen -lf -` on the key text.
  - `A04`: `echo probe | ssh-keygen -Y sign -n git -f <tmpfile holding the public key>` succeeds through the agent.
  - `P01`: `ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com` does not authenticate.
- [ ] T024 [US2] Set `agents.sandbox.signing.enable` to default `true` and `signing.publicKey` to the key from T018 in `workstation/agents/sandbox.nix`. This also adds `${runtimeDir}/ssh-agent` to `hiddenSockets` (T009). Run `nix fmt`, `nix flake check` and the Home Manager build. Break A3 (empty the sops declaration) and A4 (drop `~/.ssh`) to confirm the messages, then revert.
- [ ] T025 [US2] The user deploys. Check that `systemctl --user status ssh-agent-sign` is active. The agent runs `agent-sandbox-probe` (all rows `ok`). Do quickstart scenario 3. Confirm the signature shows as Verified on GitHub for a commit pushed by the user.

**Checkpoint**: US1 and US2 both work. This is the deployable minimum, because hiding the main agent depends on US2.

---

## Phase 5: User Story 3 - Per-project policy with agent-proposed changes (Priority: P3)

**Goal**: A project widens the baseline in its own policy file. The agent proposes changes through a prompted Edit, and shell commands cannot write the policy.

**Independent Test**: Quickstart scenario 4: fail, propose, prompt, approve, retry without restart, then reject with no change. A project policy containing `allowUnsandboxedCommands: true` does not bring back the unsandboxed retry.

- [X] T026 [US3] Render the ask rules in `workstation/agents/sandbox.nix`: append `"Edit(/.claude/settings.json)"` and `"Edit(/.claude/settings.local.json)"` to `programs.claude-code.settings.permissions.ask`, merged with the list from `workstation/agents/default.nix` (research R7). Check the rendered `~/.claude/settings.json` after building, with `jq .permissions.ask` on the activation package's file.
- [X] T027 [US3] Extend the `## Sandbox` section in `workstation/agents/agents-global.md` with the project policy contract from `contracts/project-policy.md`. Give the order of preference (`additionalDirectories`/`allowWrite`, then `allowedDomains`, then `excludedCommands`), the rule that `excludedCommands` patterns end in ` *` and never name an interpreter, and that `.claude/settings.local.json` is the default file.
- [ ] T028 [US3] Run `nix fmt`, `nix flake check` and the Home Manager build. The user deploys. Do quickstart scenario 4 in a scratch project, including the reject path and the `allowUnsandboxedCommands: true` project override. Record in `research.md` R8 whether `additionalDirectories` and `allowedDomains` applied live or needed a restart.

**Checkpoint**: US1 to US3 all work independently.

---

## Phase 6: User Story 4 - Read-only system debugging in dot-emacs (Priority: P4)

**Goal**: In the system-config repo the agent reads logs and status and builds the configuration. It cannot activate it or restart services.

**Independent Test**: Quickstart scenario 5.

- [X] T029 [US4] Add probe row `A06` (`journalctl -n1 -q` and `systemctl status --no-pager -n0 nix-daemon` succeed) to `agent-sandbox-probe` in `workstation/agents/sandbox.nix`.
- [ ] T030 [US4] Have the agent propose the dot-emacs project policy through the US3 flow: an Edit to `.claude/settings.local.json` in this repo with `permissions.additionalDirectories: ["~/Nextcloud/org_notes"]` and `sandbox.network.allowedDomains: ["search.nixos.org"]`. The user approves it. The file is gitignored and not committed.
- [ ] T031 [US4] Do quickstart scenario 5 in dot-emacs: journal, status and `nix build '.#nixosConfigurations.<hostname>.config.system.build.toplevel'` succeed. `sudo nixos-rebuild switch` is denied by rule, and `systemctl restart nix-daemon` fails on polkit.

**Checkpoint**: All stories work.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T032 [P] Update the research report artifact (https://claude.ai/artifact/8D4UEUDdrqXyLTgvFdgapY) "Known conflicts to test" section with the outcomes recorded in T017, T025 and T028.
- [X] T033 [P] Add a one-line gotcha to both `AGENTS.md` and `CLAUDE.md`: the agent sandbox is on, `agent-sandbox-probe` verifies it, and project policy lives in `.claude/settings.local.json`. Mirror the wording exactly (constitution documentation parity).
- [X] T034 Mark FR-024 done in `specs/004-agent-sandbox-policy/spec.md`, and include the already-made `config.org` change (`claude-code-ide-enable-execute-code nil`) in the same change set.
- [ ] T035 Final gate: `nix fmt` (revert unrelated churn), `nix flake check`, the Home Manager build, and `nix build '.#nixosConfigurations.<hostname>.config.system.build.toplevel'` for all three hosts in `machines/machines.nix`. Stage exactly the changed files and summarise them for the user. Do not commit.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. Can run in parallel with Phase 2.
- **Foundational (Phase 2)**: blocks all stories.
- **US1 (Phase 3)**: after Phase 2.
- **US2 (Phase 4)**: after Phase 2. Its *deployment* (T024, T025) needs US1 deployed, because T024 turns on hiding of the main agent, which only matters once the sandbox is on. T018 (manual key) can happen any time.
- **US3 (Phase 5)**: after Phase 2. It is independent of US2. Its test needs the sandbox on (US1).
- **US4 (Phase 6)**: after US1 (probe) and US3 (proposal flow for T030).
- **Polish (Phase 7)**: after the desired stories.

### Within Each Story

Option or default changes come first, then rendering, assertions, the probe
rows, the build gate, and finally deploy and validate. Tasks editing
`workstation/agents/sandbox.nix` run in sequence.

### Parallel Opportunities

- T001 and T002 (different docs), alongside T005 and T006 in Phase 2.
- T019 (`sops.nix`) and T020 (`ssh.nix`) in US2.
- T018 (manual, user) in parallel with all of US1.
- T032 and T033 in Polish.

---

## Parallel Example: User Story 2

```text
User:  T018 generate key, add to sops, register on GitHub as a Signing Key
Agent: T019 workstation/sops.nix   ||   T020 workstation/ssh.nix
then:  T021 → T022 → T023 → T024 (all workstation/agents/sandbox.nix)
```

---

## Implementation Strategy

### MVP First

1. Phases 1 and 2.
2. Phase 3 (US1): the sandbox is on, with the main agent still visible so
   signing keeps working. Validate with the probe and stop. This alone closes
   the docker, libvirt, keyring, sops-nix and D-Bus exposure.
3. Phase 4 (US2): the signing agent is in and the main agent is hidden.
   **US1 and US2 together are the recommended first deploy.**

### Incremental Delivery

4. US3: proposal flow. Until then, widen project policy by hand.
5. US4: dot-emacs profile.
6. Polish.

### Notes

- Never commit. Stage and summarise (user instructions).
- `git add` new files before any `nix build` or `nix flake check`.
- Deploys (`nixos-rebuild switch`) are run by the user.
- Commands typed at the `!` prompt run outside the sandbox, so probe
  validation must be run by the agent.
