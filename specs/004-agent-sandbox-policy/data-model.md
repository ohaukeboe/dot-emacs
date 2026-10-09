# Data Model: Agent Sandbox Policy

The "data" is configuration. There are three layers, and each has exactly one
owner.

## Baseline policy (`agents.sandbox`, Home Manager option tree)

Owned by `workstation/agents/sandbox.nix` and rendered into
`programs.claude-code.settings`. The rendered file is
`~/.claude/settings.json`, a read-only symlink into `/nix/store`.

| Field | Type | Default | Spec |
|---|---|---|---|
| `enable` | bool | `true` | FR-001 |
| `runtimeDir` | absolute path string | `"/run/user/1000"` | Socket paths. The UID is machine data, overridable per machine |
| `credentialPaths` | list of `~/`- or `/`-prefixed strings | R4 list | FR-004, FR-005 |
| `hiddenSockets` | list of absolute paths | R3 list, built from `runtimeDir`; includes `runtimeDir/ssh-agent` only when `signing.enable` | FR-006 |
| `writablePaths` | list of `~/`- or `/`-prefixed strings | `[ "~/.cache/nix" ]` | FR-007 (research R15) |
| `deniedEnvVars` | list of env-var names | `[ "GH_TOKEN" "GITHUB_TOKEN" ]` | FR-009 |
| `allowedDomains` | list of host strings | `cache.nixos.org`, `channels.nixos.org`, `github.com`, `codeload.github.com`, `api.github.com`, `objects.githubusercontent.com` | FR-012 |
| `deniedCommands` | list of Bash prefixes | `sudo`, `nixos-rebuild switch`, `nixos-rebuild boot`, `nixos-rebuild test` | FR-010 |
| `signing.enable` | bool | `true` (set to `false` until the key exists, tasks T003 and T024) | FR-019 |
| `signing.publicKey` | string matching `^ssh-ed25519 ` | none | FR-019 |
| `signing.socketName` | relative path under `runtimeDir` | `"ssh-agent-sign"` | R6 |
| `signing.secret` | sops secret name | `"ssh/agent-signing"` | R6 |

Derived, not configurable:
- `sandbox.enabled = true`, `failIfUnavailable = true`,
  `allowUnsandboxedCommands = false`, `network.allowAllUnixSockets = true`
- `sandbox.credentials.files = map deny (credentialPaths ++ hiddenSockets)`
- `sandbox.credentials.envVars = map deny deniedEnvVars`
- `permissions.deny = map Read(p/**) credentialPaths ++ map Bash(p:*) deniedCommands`
- `permissions.ask += Edit(/.claude/settings.json), Edit(/.claude/settings.local.json)`
- `settings.env` gets `SSH_AUTH_SOCK` and `GIT_CONFIG_COUNT`/`KEY_0`/`VALUE_0`
  when `signing.enable` is set

### Validation (assertions, constitution I)

1. `hiddenSockets` MUST NOT contain the Nix daemon socket, `runtimeDir/systemd`,
   or the signing socket. Hiding any of them breaks FR-007, FR-026 or FR-019.
2. `hiddenSockets` MUST contain `runtimeDir/bus` when `agents.processCap.enable`
   is set. The bus carries the keyring (R5).
3. `signing.enable` requires `signing.publicKey` and
   `config.sops.secrets.${signing.secret}` to be defined.
4. `credentialPaths` MUST include `~/.ssh` when `signing.enable` is set. The
   ControlPath change (R13) relies on it.
5. Every `credentialPaths` and `hiddenSockets` entry MUST start with `~/` or
   `/`. Relative entries resolve against the settings file directory, which is
   `~/.claude` for user settings.

## Project policy (`<project>/.claude/settings.local.json` or `.claude/settings.json`)

Owned by the project. Written only through the Edit tool after the user
approves it (FR-016). Shape: [contracts/project-policy.md](./contracts/project-policy.md).

Allowed fields: `permissions.additionalDirectories`,
`sandbox.filesystem.allowWrite`, `sandbox.filesystem.allowRead`,
`sandbox.network.allowedDomains`, `sandbox.excludedCommands`.

Ineffective at project scope, because the baseline wins: removing a
credential deny, `allowUnsandboxedCommands = true`, `filesystem.disabled`.

## Policy proposal

A transient Edit tool call on a project policy file. It always gets a
permission prompt that shows the diff.

State: `proposed`, then `approved` (written, live for filesystem lists) or
`rejected` (nothing written). There is no other path, because shell writes to
the file are blocked by protected paths.

## Agent signing identity

- Private key: sops secret `ssh/agent-signing`, decrypted by sops-nix under
  `~/.config/sops-nix/secrets/` (inside a credential path, so the sandbox
  cannot read it).
- Agent: user service `ssh-agent-sign`, socket `runtimeDir/ssh-agent-sign`,
  holding only this key.
- Public key: `agents.sandbox.signing.publicKey`. Registered on GitHub as a
  Signing key only.
- Lifecycle: the service starts after `sops-nix.service`. If the key is missing,
  the agent holds no key and `git commit` fails with a signing error. It does
  not fall back to the user's key, because `GIT_CONFIG_VALUE_0` pins the key.

## Probe set (`agent-sandbox-probe`)

A list of `(id, kind, command, expect)` rows. `kind` is `blocked` or
`allowed`, and `expect` is `fail` or `succeed`. Contract:
[contracts/probe-cli.md](./contracts/probe-cli.md).
