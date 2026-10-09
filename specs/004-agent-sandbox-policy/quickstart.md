# Quickstart: Agent Sandbox Policy

Validation guide. Implementation details are in `tasks.md`. Shapes are in
[contracts/](./contracts/).

## Prerequisites (manual, once)

1. Generate the agent signing key outside any agent session:
   `ssh-keygen -t ed25519 -N '' -C claude-agent -f /tmp/agent-signing`.
2. Add the private key to `sops/home/secrets.yaml` as `ssh/agent-signing` with
   `sops sops/home/secrets.yaml`. Then shred `/tmp/agent-signing`.
3. Put the public key into `agents.sandbox.signing.publicKey`.
4. On GitHub, under Settings → SSH and GPG keys → New SSH key, choose
   **Key type: Signing Key**. Do not add it as an authentication key.

## Build gate (constitution workflow)

```bash
git add -A specs/004-agent-sandbox-policy workstation/agents/sandbox.nix
nix fmt                     # revert unrelated churn
nix flake check
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
```

Expected: both pass. Then try each assertion: temporarily add
`"/nix/var/nix/daemon-socket"` to `hiddenSockets` and confirm that evaluation
fails with A1's message. Do the same for A2 to A5.

## Activate

```bash
sudo nixos-rebuild switch --flake .#<hostname>
systemctl --user status ssh-agent-sign       # active
SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent-sign ssh-add -l   # exactly the agent key
```

Restart Claude Code sessions. Run `/sandbox`: the Dependencies tab must not
appear, and Mode should be auto-allow.

## Scenario 1: baseline (US1, SC-001, SC-002)

In any project with no project policy, ask Claude: "run `agent-sandbox-probe`".

Expected: exit 0, every row `ok`. If any `S*` row is not `ok`, socket masking
does not hold for that path. Apply the fallback in research R3: move the
socket into a directory, or drop the group. Re-run.

## Scenario 2: fail closed (SC-008)

```bash
PATH=$(echo "$PATH" | tr : '\n' | grep -v bubblewrap | paste -sd:) claude
```

Expected: Claude Code exits at startup instead of running commands
unsandboxed.

## Scenario 3: signed commit, no push (US2, SC-003, SC-006)

In a scratch repo, ask Claude to make an empty commit, then to push.

Expected: you get the commit prompt (an existing ask rule). After that,
`git log --show-signature -1` shows a good signature from the agent key. The
push fails with `Permission denied (publickey)` or a blocked host. Your own
`git commit` in a normal terminal still signs with the main key.

## Scenario 4: proposal flow (US3, SC-004, SC-005)

In a project without a policy, ask Claude to append a line to a file in
`~/projects/<sibling>`.

Expected: the write fails with `Read-only file system`. Claude proposes an
Edit to `.claude/settings.local.json` adding `additionalDirectories` with that
sibling path, and you get a permission prompt with the diff. Approve it. The
retry succeeds without restarting the session. Repeat with a different
request and reject it: the file is unchanged.

Also confirm that a project policy containing
`"sandbox": {"allowUnsandboxedCommands": true}` does not bring back the
unsandboxed retry.

## Scenario 5: system-config debugging (US4)

In dot-emacs, ask Claude to show the last 20 journal lines for `nix-daemon`,
its status, and to build the NixOS configuration. Then ask it to run
`sudo nixos-rebuild switch` and `systemctl restart nix-daemon`.

Expected: the first three work. The `sudo` command is denied by rule, and the
restart fails on polkit authorization.

## Troubleshooting

- Approvals don't save, or 0-byte files appear under `.claude/`: run
  `claude doctor`, then delete the listed placeholders while no session is
  running in that project.
- A tool can't reach an allowed host: it probably ignores `HTTPS_PROXY`.
  Propose an `excludedCommands` entry for that one subcommand.
