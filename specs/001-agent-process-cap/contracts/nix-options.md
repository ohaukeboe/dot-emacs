# Contract: Nix options and assertions

**Feature**: `001-agent-process-cap` | **Consumers**: `workstation/agents/*.nix`,
`machines/<hostname>/config.nix`

Principle I requires the narrowest type that fits and an assertion for anything
evaluation cannot infer. This is the full surface.

## `agents.bashRewriters` (declared in `workstation/agents/default.nix`)

```nix
agents.bashRewriters = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      order = lib.mkOption { type = lib.types.ints.between 0 100; };
      executable = lib.mkOption { type = lib.types.package; };
    };
  });
  default = { };
};
```

Ordered stages of the single `PreToolUse` Bash hook. `default.nix` sorts by
`order` and renders one hook entry; no module may add a Bash `PreToolUse` hook
of its own.

## `agents.processCap` (declared in `workstation/agents/process-cap.nix`)

| Option | Type | Default |
|---|---|---|
| `enable` | `bool` | `true` |
| `foregroundSeconds` | `ints.positive` | `3600` |
| `backgroundSeconds` | `ints.positive` | `14400` |
| `graceSeconds` | `ints.positive` | `10` |
| `optOutToken` | `strMatching "[a-z][a-z0-9-]*"` | `"nocap"` |

The sensitive-prefix list is **not** part of `processCap`. As built it is
`agents.sensitiveBashPrefixes` (`listOf str`) in
`workstation/agents/default.nix`, next to the guard that consumes it and the
`permissions.ask` rules it renders — the cap module has no use for it.

All configuration sits under `mkIf cfg.enable`, including the
`agents.bashRewriters.processCap` contribution, so a machine with the cap off
gets a chain without it and no assertions from it (Principle V).

## Assertions

Each names the file and the fix, as Principle I requires.

1. `foregroundSeconds >= 60` — a cap under a minute kills ordinary work.
2. `backgroundSeconds >= foregroundSeconds` — background work exists to run
   longer; the reverse ordering is always a typo.
3. `graceSeconds < foregroundSeconds` — a grace period at or above the
   allowance doubles the effective cap.
4. `agents.sensitiveBashPrefixes != [ ]` whenever any rewriter is registered —
   an empty list silently disables the re-assertion that keeps ask rules
   meaningful (R9). Declared in `workstation/agents/default.nix`.
5. Every `order` in `agents.bashRewriters` is unique — equal orders reintroduce
   the nondeterminism ADR 0003 removes.
6. `agents.bashRewriters.processCap.order` is the maximum order in the set — a
   stage after the cap would rewrite text already inside the wrapper payload.

## Single source of truth

`agents.sensitiveBashPrefixes` holds bare prefixes (`git commit`, `rm -rf`).
The guard matches them directly, and
`programs.claude-code.settings.permissions.ask` is rendered from the same list
with `map (p: "Bash(${p}:*)")`, concatenated with the MCP rules (Principle IV).
Changing the list in one place changes both.
