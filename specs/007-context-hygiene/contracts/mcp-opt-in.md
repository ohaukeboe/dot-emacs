# Contract: per-repository tool-server opt-in

## Plugins shipped in `~/.claude/skills`

| Plugin dir   | `plugin.json` name | Server            | Default |
|--------------|--------------------|-------------------|---------|
| `hm-mobile`  | `hm-mobile`        | `mobile-mcp`      | off     |
| `hm-browser` | `hm-browser`       | `chrome-devtools` | off     |

Each plugin directory contains:

```text
.claude-plugin/plugin.json   {"name": "...", "defaultEnabled": false, ...}
.mcp.json                    {"mcpServers": {"<server>": {"type": "stdio", ...}}}
```

## Opting a repository in

Add this to the repository's `.claude/settings.local.json` (personal,
gitignored) or `.claude/settings.json` (shared):

```json
{ "enabledPlugins": { "hm-browser@skills-dir": true } }
```

In this repository and any other whose sandbox write-denies
`.claude/settings*.json`, the user makes that edit, not the agent.

## Tool-name change

| Before                              | After                                       |
|-------------------------------------|---------------------------------------------|
| `mcp__plugin_hm_mobile-mcp__*`      | `mcp__plugin_hm-mobile_mobile-mcp__*`       |
| `mcp__plugin_hm_chrome-devtools__*` | `mcp__plugin_hm-browser_chrome-devtools__*` |

Every quoted prefix in `workstation/agents/skills/user-testing/` is updated
to match.
