# Quickstart: validating the Agent Process Runtime Cap

**Feature**: `001-agent-process-cap` | **Date**: 2026-09-23

Runnable checks that prove the feature works, in the order to run them. Details
of the interfaces live in [`contracts/`](./contracts/); the entities are in
[`data-model.md`](./data-model.md).

**No automated test ships with this feature.** The durable regression test was
withdrawn by the owner during implementation, so steps 3 and 4 below are manual
procedures rather than one `nix build`. What was actually checked once, against
the built artifacts, is recorded in [`research.md`](./research.md) R14.

## Prerequisites

- NixOS, `systemd --user` session available (`systemctl --user is-system-running`).
- Every new file `git add`ed — the flake sees only tracked files.
- `systemd` ≥ 253 for `RuntimeMaxSec` on transient scopes (261.2 here).

## 1. Evaluation gate

```bash
nix fmt                                   # then revert unrelated churn
nix flake check                           # baseline 47.1 s on work-laptop
nix build '.#nixosConfigurations.work-laptop.config.system.build.toplevel'
```

Expected: both succeed. `nix flake check` covers `shellcheck` on the chain
runner and the helper, since both are `writeShellApplication`.

## 2. Assertions actually fire

Each of the six assertions in [`contracts/nix-options.md`](./contracts/nix-options.md)
must fail evaluation when violated. Check them one override at a time:

```bash
nix eval --impure --expr '
  let f = builtins.getFlake "/home/oskar/projects/dot-emacs";
      c = f.nixosConfigurations.work-laptop.extendModules {
        modules = [ { home-manager.users.oskar.agents.processCap.foregroundSeconds = 30; } ];
      };
  in c.config.system.build.toplevel.drvPath'
```

Expected: `Failed assertions:` naming the option, the file and the fix. The six
cases are `foregroundSeconds = 30`, `backgroundSeconds` below `foregroundSeconds`,
`graceSeconds` above it, `sensitiveBashPrefixes = lib.mkForce [ ]`, a second
stage at `order = 90`, and a stage at `order = 95`. All six were confirmed to
fire. An assertion that does not fire is a missing gate, not a passing test.

## 3. Kill, grace period and orphan (manual)

Lower the allowance so the check takes a minute rather than an hour: set
`foregroundSeconds = 60` and `graceSeconds = 2` in
`workstation/agents/process-cap.nix`, rebuild, and take the helper's store path
from

```bash
nix eval --raw '.#nixosConfigurations.work-laptop.config.home-manager.users.oskar.agents.tools.process-cap.packages' \
  --apply 'ps: toString (map (p: "${p}/bin/agent-process-cap") ps)'
```

Then, with `$H` as that path:

```bash
# honours SIGTERM: expect exit 143 at ~60 s
$H run fg "$(printf 'sleep 600' | base64 -w0)"

# ignores SIGTERM: expect exit 137 at ~62 s — the grace period, then the kill
$H run fg "$(printf 'trap "" TERM; while true; do sleep 0.3; done' | base64 -w0)"

# orphan: launcher SIGKILLed 2 s in, child re-parented, still reaped at the cap
setsid bash -c "$H run fg \"$(printf 'while true; do sleep 0.3; done' | base64 -w0)\" & sleep 2; kill -9 \$\$" &
```

Expected in all three: a `[process-cap] terminated after the fg runtime cap of
60s` line on stderr, no `Terminated  systemd-run ...` notice anywhere, no
process left behind, and no leftover unit in
`systemctl --user list-units --type=scope --all`.

**Restore the real allowances afterwards.**

## 4. Transparency battery (manual)

Run each of at least 15 shell constructs twice with the same stdin — once
through `bash -c "$c"`, once through `$H run fg "$(printf '%s' "$c" | base64 -w0)"`
— and diff stdout, stderr and exit status. Cover pipes, each redirection form, a
heredoc, `$VAR`, `$$`, both quoting styles, a subshell, a non-zero exit, a stdin
consumer, a multi-statement command, a loop, and `cd` followed by a command.

Expected: no differences (SC-004). The three failures this catches, all of which
it did catch: `$$` collapsing to a literal `$` without
`--expand-environment=no`; the shell's `Terminated  ...` notice leaking into
captured stderr; and a trailing heredoc swallowing anything appended to the
command text (research.md R12).

## 5. Cap fires on a real hang

```bash
agent-process-cap run fg "$(printf 'sleep 600' | base64 -w0)"; echo "exit=$?"
```

With `foregroundSeconds` temporarily lowered for the check. Expected: exits
`143` (or `137` if the command ignores `SIGTERM`) at the cap, and the kill is
visible:

```bash
journalctl --user --since -10min -g claude-cap -o short-iso
```

Expected: `Started claude-cap fg …`, `Scope reached runtime time limit.
Stopping.`, `Failed with result 'timeout'`.

## 6. Opt-out works

```bash
# through the chain, not the helper: the token is the stage's business
echo '{"tool_name":"Bash","tool_input":{"command":"nocap sleep 1"}}' | <chain-runner>
```

Expected: `updatedInput.command` is `sleep 1`, unwrapped — token stripped, no
cap (FR-006).

## 7. Sensitive commands still prompt

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | <chain-runner>
```

Expected: output carries `permissionDecision: "ask"` naming the matched pattern,
alongside the wrapped `updatedInput` (R9). Without this the wrapper would move
`git commit` off position 0 and a prefix ask rule would no longer match it.

## 8. Fail open

```bash
PATH=/nonexistent agent-process-cap run fg "$(printf 'echo alive' | base64 -w0)"
```

Expected: prints `alive`, exit 0 — uncapped rather than broken (FR-007).

## 9. Deploy and observe

```bash
sudo nixos-rebuild switch --flake .#work-laptop
```

Then the two acceptance observations that can only be made on the live machine:

- **SC-002**: after a week, `journalctl --user -g claude-cap --since -7d` lists
  every kill with its command, and no agent-started process is older than its
  allowance (`ps -eo pid,etime,cmd --sort=-etime | head`).
- **SC-005**: at idle, package temperature and fan back at the baseline —
  approximately 57 °C and 2525 RPM (`sensors`), against the 80 °C / 3180 RPM
  seen with orphans present.

The feature is not done until step 9's observations hold; that is what the
originating issue's acceptance criteria require.
