# Contract: context status line command

Executable: `lib.getExe contextStatusline`, a `writeShellApplication`
registered as `programs.claude-code.settings.statusLine.command`.

## Input

Claude Code's status-line JSON on stdin. The only fields read are:

| Field                                | Use                                 |
|--------------------------------------|-------------------------------------|
| `.context_window.total_input_tokens` | context size                        |
| `.session_id`                        | read by the replayed caveman script |

The caveman script reads its mode from `$CLAUDE_CONFIG_DIR` or
`$HOME/.claude`, which the harness sets.

## Output

One line on stdout with no trailing newline, made of two segments:

1. The caveman badge, exactly as `caveman-statusline.sh` prints it. It is
   empty when caveman is disabled, or when no mode is active.
2. When the size is known: a space (only if the badge is non-empty), then
   the size in one of three styles.

| Tokens `t`                       | Text            | Style (SGR)        |
|----------------------------------|-----------------|--------------------|
| `t <= warnTokens`                | `round(t/1e3)K` | `2` dim            |
| `warnTokens < t <= strongTokens` | `round(t/1e3)K` | `33` yellow        |
| `t > strongTokens`, `t < 1e6`    | `round(t/1e3)K` | `1;37;41` bold/red |
| `t >= 1e6`                       | `x.yM`          | `1;37;41` bold/red |

Each styled segment ends with `\033[0m`.

`x.yM` is truncated to one decimal, not rounded: 1250000 prints `1.2M`, and
1000000 prints `1.0M`.

## Failure behaviour

- The exit code is always 0.
- Missing, null, `0`, non-numeric or unparsable input prints the badge
  segment only.
- A failing badge script prints the size segment only.

## Build-time test

`tests/context-statusline.nix`, registered in `flake.nix` `checks`. It feeds
these inputs and asserts the output byte for byte:

- `{}`
- `null`
- `0`
- garbage text
- `38211` (neutral)
- `200000` (neutral)
- `200001` (warning)
- `412000` (strong)
- `1250000` (strong)
- `1000000` (strong, `1.0M`)
- a badge script that exits 1 (size only)

It runs with a temporary HOME holding `.claude/.caveman-active=full`.
