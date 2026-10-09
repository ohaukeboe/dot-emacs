# ADR 0004 — Claude Code's built-in sandbox with a Nix-generated baseline

**Status:** Accepted (2026-10-08)

## Context

Claude Code runs in auto mode on these machines with the user's full
authority. Two of the user's group memberships, `docker` (with the rootful
`/run/docker.sock`) and `libvirtd`, are equivalent to root. The session D-Bus
serves gnome-keyring's `org.freedesktop.secrets`, sops-nix decrypts keys into
`~/.config/sops-nix/secrets`, and the main ssh-agent holds a key that both
signs commits and authenticates pushes.

The threat model is a cooperative agent deciding on its own to do something
the user did not ask for: restart a container, read a key while debugging,
apply the system configuration. Prompt injection and deliberate evasion are
out of scope. Under that model, controls that match command text, such as
permission rules and the auto mode classifier, are meaningful.

An earlier attempt turned the built-in sandbox on and was reverted. The note
in `workstation/agents/default.nix` said it "broke nix daemon access,
ssh-agent signing and nested sessions". The cause was Unix sockets. On Linux
the optional seccomp filter blocks every Unix socket, and per-path socket
allowlisting (`allowUnixSockets`) is macOS-only. The Nix daemon and ssh-agent
are both Unix sockets.

The alternatives were surveyed in
https://claude.ai/artifact/8D4UEUDdrqXyLTgvFdgapY: sandbox-runtime around the
whole process, ai-jail, jail.nix/nixpak, systemd-nspawn, microvm.nix, and a
separate Unix user. All of them confine more, including the file tools, hooks
and MCP servers. All of them would also break the Emacs integration, which
launches `claude` inside Emacs, and none of them provides an approval flow for
widening access.

## Decision

**Use Claude Code's built-in sandbox, configured from Nix, in three layers.**

1. **Sandbox baseline** (`agents.sandbox`, `workstation/agents/sandbox.nix`),
   rendered into the read-only user settings:
   - `allowAllUnixSockets = true`, so the Nix daemon and a signing agent work.
   - Dangerous sockets and credential paths are hidden by path as
     `credentials.files` denies, which no project scope can remove.
   - `allowUnsandboxedCommands = false`: no unconfined retry.
   - `failIfUnavailable = true`: no silent fallback when bwrap is missing.
   - `Read()` deny rules generated from the same credential list, because the
     Read tool runs outside the sandbox.
2. **Project policy**: per-project additions in `.claude/settings.local.json`.
   Shell commands cannot write it (sandbox protected path). The Edit tool can,
   but `ask` rules on both project settings files make every change a prompt
   the user approves, even in auto mode.
3. **Auto mode classifier**: unchanged. It covers actions outside the sandbox.

Commits are signed by a dedicated signing-only key in its own ssh-agent. The
main agent is hidden. The session bus is hidden. Inside the sandbox the process
cap uses `timeout` instead of `systemd-run`, because the user manager rejects
sandboxed callers. The sandbox's `--die-with-parent` and private PID namespace
already stop commands outliving their session.

## Consequences

- The file tools, hooks, MCP servers and LSP servers still run with full user
  rights. Read denies and the classifier cover accidental use only.
- Agent commands lose the process cap's per-command memory scope. The
  session's scope still bounds them. Daemons started with `nocap` die when
  their command returns.
- The sandbox masks a missing `.gitmodules`, which breaks Nix flake
  evaluation of git repos inside it (research R17).
- Whether masking a socket path blocks `connect()` is not documented. The
  `agent-sandbox-probe` command checks it in the real session, and research R3
  in `specs/004-agent-sandbox-policy/` records the fallback.
- If prompt injection enters the threat model, this ADR is superseded by a
  whole-process boundary.
- Supersedes the "Keep the Claude Code sandbox off" comment in
  `workstation/agents/default.nix`.
