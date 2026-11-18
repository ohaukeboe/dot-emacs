# Contract: Usage Record

The only interface between `workstation/agents/usage.nix` (writers) and
`modules/mango` (readers). Neither side reads the other's Nix options.

Directory: `$XDG_STATE_HOME/agent-usage/` (default `~/.local/state/agent-usage/`).

## `limits.json`

Written by `agent-usage.service` from Anthropic's OAuth usage endpoint
(`/api/oauth/usage`, with the token Claude Code keeps in
`~/.claude/.credentials.json`), and by `context-statusline` on every
status-line render that carries rate limits. Claude Code passes those only
near a limit, so the service is the main source. Written to a temporary
file in the same directory, then renamed.

```json
{
  "updated_at": 1794660000,
  "session": { "used_percentage": 42, "resets_at": 1794668040 },
  "weekly":  { "used_percentage": 61, "resets_at": 1794992400 }
}
```

- Percentages are numbers from 0 to 100; times are epoch seconds.
- `resets_at` may be `null` for a window that has not started.
- A render without rate limits, an expired token or a failed request leaves
  the file untouched; the service never refreshes the token.
- A failed write must not change the status line's output or exit code.

## `tokens.json`

Written by `agent-usage.service` (timer: every 5 minutes, and at login).

```json
{
  "updated_at": 1794660000,
  "days": [ { "date": "2026-11-08", "tokens": 800000 } ],
  "models": [ { "model": "claude-opus-5-5", "tokens": 9100000 } ],
  "week_tokens": 12900000
}
```

- `days` has exactly 7 entries, oldest first, today last; days without use
  have `tokens: 0`.
- On failure the collector writes the previous content plus
  `"error": "<one line>"`, or `{"updated_at": …, "error": …}` if there is none.

## Refresh

Readers may request a refresh with
`systemctl --user start agent-usage.service`. If the unit does not exist the
call fails and the reader ignores it.

## Reader rules

- Missing `limits.json`: show no usage pill.
- Missing `tokens.json`: show limits only.
- Unparseable file: treat as missing.
- Readers never write in this directory.
