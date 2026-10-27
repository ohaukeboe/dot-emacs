# Baseline: Agent Context Hygiene (2026-10-27)

The SC-006 baseline, taken before any change from this feature. Host:
`dig-laptop` (`hostname` checked). Repository HEAD: `40999d6`.

## Tool servers

- `programs.mcp.servers` in `workstation/agents/mcp-servers.nix`: **9**
  entries. Evaluated with
  `nixosConfigurations.dig-laptop.config.home-manager.users.oskar.programs.mcp.servers`.
- The same 9 servers are connected in a session in this repository, all
  through the `hm` plugin (`mcp__plugin_hm_<server>__*`): chrome-devtools,
  codebase-memory, context7, elisp-dev-mcp, github-mcp, kagi, lsp-mcp,
  mcp-nixos and mobile-mcp.

## Described-skill count, per host

Built `nixosConfigurations.<h>.config.home-manager.users.oskar.home-files`
for each host, then counted:

- **Skills**: `.claude/skills/*/SKILL.md` without
  `disable-model-invocation: true`. No skill has a `skillOverrides` key yet;
  the generated `settings.json` has no `skillOverrides`.
- **Beads commands**: `plugins/beads/skills/beads/commands/*.md` in
  `pkgs.nvSources.beads.src`
  (`/nix/store/v1zwx9xff555gias10rg0cf1n4p45j1v-source`, the same on every
  host) without the key. None of the 29 files has it.

| Host        | SKILL.md total | Skills described | Beads commands | Described |
|-------------|----------------|------------------|----------------|-----------|
| work-laptop | 66             | 29               | 29             | 58        |
| desktop     | 66             | 29               | 29             | 58        |
| laptop      | 66             | 29               | 29             | 58        |
| dig-laptop  | 71             | 34               | 29             | 63        |

dig-laptop has 5 more: the `punkt-*` skills. Every host's `settings.json`
sets `skillListingBudgetFraction = 0.02`.

## Session skill listing (dig-laptop)

The skill listing a session in this repository receives, counted from a
Claude Code session started on 2026-10-27:

| Source                                    | Listed |
|-------------------------------------------|--------|
| User skills (`~/.claude/skills`)          | 34     |
| Project skills (`.claude/skills`)         | 13     |
| `beads:` commands                         | 27     |
| `beads:beads` skill                       | 1      |
| Other plugins (security, claude-md)       | 4      |
| Built-in skills                           | 18     |
| **Total**                                 | **97** |

The listing shows 27 of the 29 beads command files: `prime` and `template`
are not listed.

## `bd prime`

`bd prime | wc -c`: **6992** bytes.
