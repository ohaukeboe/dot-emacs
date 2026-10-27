# Data Model: Agent Context Hygiene

This feature has no database. Its "data" is the typed Home Manager options
that hold each configurable value (constitution Principle I), the settings
keys they produce, and one record kept in beads.

## Typed options

The options are declared in the module named in each table. Everything is
evaluated at build time, and an invalid value fails `nix flake check`.

### `agents.context` (`workstation/agents/statusline.nix`)

| Option              | Type                          | Default  | Feeds  |
|---------------------|-------------------------------|----------|--------|
| `statusLine.enable` | `bool`                        | `true`   | FR-001 |
| `warnTokens`        | `ints.positive`               | `200000` | FR-002 |
| `strongTokens`      | `ints.positive`               | `400000` | FR-002 |
| `autoCompactTokens` | `ints.between 100000 1000000` | `400000` | FR-010 |

Assertions, each with a message naming `workstation/agents/statusline.nix`
and the fix:

- `warnTokens < strongTokens`
- `autoCompactTokens >= strongTokens`. The strong warning should show before
  the agent compacts, otherwise it never shows.

### `agents.mcp.optIn` (`workstation/agents/mcp-servers.nix`)

| Option         | Type                                | Default | Feeds  |
|----------------|-------------------------------------|---------|--------|
| `servers`      | `listOf (enum [ ... ])` (2 servers) | both    | FR-019 |
| `outputTokens` | `ints.between 1000 100000`          | `10000` | FR-018 |

- Each server in `servers` gets its own default-off plugin (`hm-mobile`,
  `hm-browser`).
- A server not in the list stays in the global set.
- Opencode receives every server either way.

### `agents.skillOverrides` (`workstation/agents/skills.nix`)

- **Type**: `attrsOf (enum [ "on" "name-only" "user-invocable-only" "off" ])`
- **Default**: `{}`

- The value is merged from every skill source.
- `mkSkillEntry` gets an optional `listing` field.
- `machines/dig-laptop/default.nix` adds the `punkt-*` keys.
- Written verbatim to `programs.claude-code.settings.skillOverrides`.

### Plain settings (no option; the value is fixed by the spec)

| Settings key                    | Value        | Module                           |
|---------------------------------|--------------|----------------------------------|
| `autoMemoryEnabled`             | `false`      | `workstation/agents/default.nix` |
| `env.RTK_SUPPRESS_HOOK_WARNING` | `"1"`        | `workstation/agents/rtk.nix`     |
| `permissions.deny`              | 5 task tools | `workstation/agents/beads.nix`   |
| `skillListingBudgetFraction`    | removed      | `workstation/agents/default.nix` |

## Runtime entities

### Context size

- **Source:** `.context_window.total_input_tokens` from the status-line stdin
  JSON.
- **Type:** a non-negative integer.
- **State:** derived on every render, never stored:

```text
missing | null | 0 | not a number  ->  no-data  (badge only)
1 .. warnTokens                     ->  neutral
warnTokens+1 .. strongTokens        ->  warning
> strongTokens                      ->  strong
```

### Handoff note (stored in beads)

- **Where:** appended to an issue's `notes` field with `bd note <id> --stdin`.
  Earlier notes are kept.
- **Shape:** at most 20 lines.

```text
Handoff YYYY-MM-DD
Tried: <approaches attempted>
Failed: <what failed and why>
Next: <the next thing to try>
```

- **Lifecycle:** written once per reset. The issue stays in `in_progress`. A
  new session reads the note through `bd show <id>` after `bd prime` points
  it there.

### Tool-server loadout

- **Global default:** every server in `programs.mcp.servers`, minus
  `agents.mcp.optIn.servers`.
- **Per-repository opt-in:** `enabledPlugins."hm-mobile@skills-dir" = true`
  (or `hm-browser`) in the repository's `.claude/settings.local.json` or
  `.claude/settings.json`. Local scope overrides user scope.
