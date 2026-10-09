# Contract: `agent-sandbox-probe`

A `writeShellApplication` on the Home Manager path. It is meant to be run *by
the agent*, because commands typed at the `!` prompt run outside the sandbox.

```text
agent-sandbox-probe [--json]
```

Runs every probe, prints one row per probe, and exits 0 only if every probe
matches its expectation. Exit 1 means at least one mismatch. Exit 2 means it
detected that it is not inside the sandbox: a write to `$HOME/.agent-sandbox-probe`
succeeded. In that case it removes the file and refuses to report.

## Output

```text
ID   KIND     EXPECT   RESULT  PROBE
B01  blocked  fail     ok      read ~/.ssh
B02  blocked  fail     ok      read ~/.config/sops-nix/secrets
…
A01  allowed  succeed  ok      nix-shell -p hello --run hello
…
```

`--json` prints an array of `{id, kind, expect, result, probe, detail}`.

## Probes

Generated from the same option values as the policy, so a new
`credentialPaths` or `hiddenSockets` entry automatically gets a probe.

| ID | Kind | Probe | Spec |
|---|---|---|---|
| B01..Bn | blocked | `ls`/`cat` of each `credentialPaths` entry | FR-004 |
| S01..Sn | blocked | `socat -u OPEN:/dev/null UNIX-CONNECT:<path>` for each socket file, and for each socket under each hidden directory | FR-006 |
| E01..En | blocked | each `deniedEnvVars` entry is unset | FR-009 |
| W01 | blocked | write to `~/.bashrc` | FR-011 |
| W02 | blocked | write to `./.claude/settings.local.json` | FR-011 |
| W03 | blocked | write to `./.git/hooks/probe` | FR-011 |
| N01 | blocked | `curl -sS https://example.com` | FR-012 |
| P01 | blocked | `SSH_AUTH_SOCK=$SSH_AUTH_SOCK ssh -o BatchMode=yes -T git@github.com` | FR-019, FR-022 |
| A01 | allowed | `nix-shell -p hello --run hello` | FR-007 |
| A02 | allowed | `nix build --no-link nixpkgs#hello` | FR-007 |
| A03 | allowed | `ssh-add -l` lists exactly one key, matching `signing.publicKey` | FR-019 |
| A04 | allowed | sign a test buffer with `ssh-keygen -Y sign -n git` using the inline key | FR-019 |
| A05 | allowed | `systemd-run --user --scope -q --collect true` | FR-026 |
| A06 | allowed | `journalctl -n1 -q` and `systemctl status --no-pager -n0 nix-daemon` | FR-023 |
| A07 | allowed | `curl -sS -o /dev/null https://cache.nixos.org/nix-cache-info` | FR-012 |
| I01 | info | `/dev/kvm` present (yes/no, never a failure) | R10 |

Commands use `lib.getExe` references (constitution I). The script never
prints the contents of anything it manages to read. A successful read is
reported only as `LEAK: <path>`.
