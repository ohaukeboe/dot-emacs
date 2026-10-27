# Contract: deployed `~/.claude/settings.json`

The keys this feature adds, changes or removes in the generated user
settings. Nothing outside this list changes.

| Key                                      | Expected value                      |
|------------------------------------------|-------------------------------------|
| `statusLine.type`                        | `"command"`                         |
| `statusLine.command`                     | store path of `contextStatusline`   |
| `autoCompactWindow`                      | `400000`                            |
| `autoMemoryEnabled`                      | `false`                             |
| `env.MAX_MCP_OUTPUT_TOKENS`              | `"10000"`                           |
| `env.RTK_SUPPRESS_HOOK_WARNING`          | `"1"`                               |
| `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW`    | absent                              |
| `permissions.deny` (contains)            | `TodoWrite`, `TaskCreate`,          |
|                                          | `TaskGet`, `TaskList`, `TaskUpdate` |
| `permissions.deny` (does not contain)    | `TaskStop`, `TaskOutput`,           |
|                                          | `SendMessage`                       |
| `skillOverrides`                         | per `data-model.md` table           |
| `skillListingBudgetFraction`             | absent (harness default 0.01)       |
| `enabledPlugins."hm-mobile@skills-dir"`  | `false`                             |
| `enabledPlugins."hm-browser@skills-dir"` | `false`                             |

To check, build the home configuration and run `jq` on the generated
`settings.json` in the activation package. The quickstart gives the command.
