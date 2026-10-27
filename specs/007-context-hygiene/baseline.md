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

## After (2026-10-27, T047)

Taken with the feature applied to the working tree (HEAD `9a8fe3a` plus the
staged feature changes). Same method as above: build-derived only, the
live-session count is T048.

### Tool servers, per host

`programs.mcp.servers` now has **7** entries on every host: codebase-memory,
context7, elisp-dev-mcp, github-mcp, kagi, lsp-mcp and mcp-nixos.
mobile-mcp and chrome-devtools moved to the opt-in plugins `hm-mobile` and
`hm-browser` (`agents.mcp.optIn.servers`), disabled in `enabledPlugins`.

| Host        | Before | After | Fewer |
|-------------|--------|-------|-------|
| work-laptop | 9      | 7     | 2     |
| desktop     | 9      | 7     | 2     |
| laptop      | 9      | 7     | 2     |
| dig-laptop  | 9      | 7     | 2     |

### Described-skill count, per host

A skill counts as described only if its `SKILL.md` lacks
`disable-model-invocation: true` and `settings.json` `skillOverrides` does
not set it to `name-only`, `user-invocable-only` or `off`. Beads commands
are counted in the patched marketplace `beads-marketplace-no-auto`
(`/nix/store/ncpfwnql3wlbpvs22xpnv22mw7cp4k5j-…`, the same on every host),
where all 29 now carry the key.

| Host        | SKILL.md | No-invoke | Overridden | Skills | Beads | Described |
|-------------|----------|-----------|------------|--------|-------|-----------|
| work-laptop | 66       | 38        | 12         | 16     | 0     | 16        |
| desktop     | 66       | 38        | 12         | 16     | 0     | 16        |
| laptop      | 66       | 38        | 12         | 16     | 0     | 16        |
| dig-laptop  | 71       | 38        | 17         | 16     | 0     | 16        |

- Overridden: `spec`, `build`, `check`, `backprop` (`name-only`) and the 8
  `understand*` skills (`user-invocable-only`); dig-laptop adds the 5
  `punkt-*` skills (`user-invocable-only`).
- `cavecrew` is no longer installed as a user skill. `bead-handoff` is new and
  has `disable-model-invocation: true`, so the totals are unchanged.
- `skillListingBudgetFraction` is no longer set.

### SC-006

| Host        | Described before | Described after | Fewer | MCP fewer | SC-006 |
|-------------|------------------|-----------------|-------|-----------|--------|
| work-laptop | 58               | 16              | 42    | 2         | holds  |
| desktop     | 58               | 16              | 42    | 2         | holds  |
| laptop      | 58               | 16              | 42    | 2         | holds  |
| dig-laptop  | 63               | 16              | 47    | 2         | holds  |
