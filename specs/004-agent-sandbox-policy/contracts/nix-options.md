# Contract: `agents.sandbox` Home Manager options

Module: `workstation/agents/sandbox.nix`, imported from
`workstation/agents/default.nix`. All config is under `lib.mkIf cfg.enable`.
When the module is disabled it contributes nothing (constitution V), and
`settings.sandbox.enabled` falls back to `false`.

```nix
options.agents.sandbox = {
  enable          = mkOption { type = bool; default = true; };
  runtimeDir      = mkOption { type = strMatching "^/run/user/[0-9]+$"; default = "/run/user/1000"; };
  credentialPaths = mkOption { type = listOf (strMatching "^(~/|/).+"); default = [ /* research R4 */ ]; };
  hiddenSockets   = mkOption { type = listOf (strMatching "^/.+"); default = [ /* research R3, from runtimeDir */ ]; };
  writablePaths   = mkOption { type = listOf (strMatching "^(~/|/).+"); default = [ "~/.cache/nix" ]; };   # research R15
  deniedEnvVars   = mkOption { type = listOf (strMatching "^[A-Z_][A-Z0-9_]*$"); default = [ "GH_TOKEN" "GITHUB_TOKEN" ]; };
  allowedDomains  = mkOption { type = listOf str; default = [ /* data-model.md */ ]; };
  deniedCommands  = mkOption { type = listOf str; default = [ "sudo" "nixos-rebuild switch" "nixos-rebuild boot" "nixos-rebuild test" ]; };
  signing = {
    enable     = mkOption { type = bool; default = false; };   # true once the key exists (T024)
    publicKey  = mkOption { type = nullOr (strMatching "^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$"); default = null; };
    socketName = mkOption { type = strMatching "^[A-Za-z0-9._-]+$"; default = "ssh-agent-sign"; };
    secret     = mkOption { type = str; default = "ssh/agent-signing"; };
  };
};
```

## Rendered settings (excerpt, user scope)

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": { "allowWrite": ["~/.cache/nix"] },
    "network": { "allowAllUnixSockets": true, "allowedDomains": ["…"] },
    "credentials": {
      "files":   [{ "path": "~/.ssh", "mode": "deny" }, "…"],
      "envVars": [{ "name": "GH_TOKEN", "mode": "deny" }, "…"]
    }
  },
  "permissions": {
    "deny": ["Read(~/.ssh/**)", "…", "Bash(sudo:*)", "…"],
    "ask":  ["…existing…", "Edit(/.claude/settings.json)", "Edit(/.claude/settings.local.json)"]
  },
  "env": {
    "SSH_AUTH_SOCK": "/run/user/1000/ssh-agent-sign",
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "user.signingkey",
    "GIT_CONFIG_VALUE_0": "key::ssh-ed25519 …"
  }
}
```

The existing line `programs.claude-code.settings.sandbox.enabled = false` in
`default.nix` is removed. The sandbox module owns the key.

## Assertions

| # | Condition | Message names |
|---|---|---|
| A1 | No `hiddenSockets` entry equals or contains `/nix/var/nix/daemon-socket`, `${runtimeDir}/systemd` or `${runtimeDir}/${signing.socketName}` | `workstation/agents/sandbox.nix`, the entry, the FR it would break |
| A2 | `agents.processCap.enable` implies `"${runtimeDir}/bus"` is in `hiddenSockets` | keyring over D-Bus (R5) |
| A3 | `signing.enable` implies `signing.publicKey` is set and `config.sops.secrets ? ${signing.secret}` | `workstation/sops.nix` |
| A4 | `signing.enable` implies `"~/.ssh"` is in `credentialPaths` | ControlPath (R13) |
| A5 | `config.programs.ssh.settings."*".ControlPath` does not start with `/tmp` | `workstation/ssh.nix` |

## Related changes outside the module

| File | Change |
|---|---|
| `workstation/agents/process-cap.nix` | Fail-open check also accepts `$XDG_RUNTIME_DIR/systemd/private` (R5) |
| `workstation/ssh.nix` | `ControlPath = "~/.ssh/cm-%C"`. New `systemd.user.services.ssh-agent-sign` (R6) |
| `workstation/sops.nix` | `"ssh/agent-signing" = { };` |
| `sops/home/secrets.yaml` | New key, added by the user with `sops` (manual, see quickstart) |
| `workstation/agents/agents-global.md` | `## Sandbox` guidance (R7, R14) |
| `home.packages` | `bubblewrap`, `socat` (R11), `agent-sandbox-probe` |
