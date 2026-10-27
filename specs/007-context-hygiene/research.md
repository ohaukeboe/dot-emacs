# Phase 0 Research: Agent Context Hygiene

Seven research agents covered the seven unknown areas in parallel. An eighth
agent then tried to refute every claim the implementation depends on. Of 57
claims, 50 were confirmed, 2 refuted and 5 are unverifiable from documents.
The refuted and unverifiable claims are listed at the end, each with how it is
handled. Sources: the Claude Code docs at `code.claude.com/docs/en/*.md`, as
read on 2026-10-27, the installed binaries and their sources, and this
repository at `40999d6`.

## R1. Context-size status line (FR-001–003)

**Decision.**

- Add a new module, `workstation/agents/statusline.nix`, that owns
  `programs.claude-code.settings.statusLine`.
- Its command is a `writeShellApplication` (jq, coreutils). It works in four
  steps:
  1. It buffers stdin once.
  2. When `agents.tools.caveman.enable` is on, it replays stdin into the
     upstream `caveman-statusline.sh`, called by its store path, to get the
     badge.
  3. It appends the size from `.context_window.total_input_tokens`, formatted
     as `38K` or `1.2M`.
  4. It styles the size neutral (dim), warning (yellow, above `warnTokens`) or
     strong (bold on red, above `strongTokens`). Each comparison is a strict
     `>`.
- Missing, null, non-numeric or `0` values, or stdin that cannot be parsed,
  print the badge alone.
- Every step ends in `|| true`, so the script always exits 0.
- Remove the `statusLine` block from `workstation/agents/caveman.nix:74-79`.

**Rationale.**

- The harness allows only one `statusLine` command, so one module must own it.
- `caveman.nix` currently sets the status line only when caveman is enabled.
  Moving it out keeps the size visible when caveman is off.
- `total_input_tokens` is the absolute size of the context window (input plus
  cache reads and writes). The docs say it is `0` before the first response.
- `used_percentage` depends on the window size, so it cannot express absolute
  200K and 400K points.
- `exceeds_200k_tokens` also counts output and has no 400K point.
- The docs allow ANSI colours.
- `writeShellApplication` turns on `errexit`, and jq exits 5 on garbage input.
  The docs say a non-zero exit blanks the line, hence the `|| true` guards.

**Alternatives considered.**

| Alternative                        | Why rejected                                  |
|------------------------------------|-----------------------------------------------|
| Wrap the line inside `caveman.nix` | Couples the size to caveman being on          |
| Inline jq string in settings       | No shellcheck, which Principle I forbids      |
| Reimplement the badge              | Duplicates upstream's mode-file safety checks |
| `used_percentage`                  | Relative to a 200K or 1M window, not absolute |

The Assumptions in `data-model.md` cover the 200 001–200 499 rounding
artefact, which is accepted.

## R2. Harness settings: auto-compact, auto memory, MCP limit (FR-010/011/013/018)

**Decision.** Set three keys in `programs.claude-code.settings`, each fed from
a typed option (see `data-model.md`):

| Key                         | Value           | Requirement |
|-----------------------------|-----------------|-------------|
| `autoCompactWindow`         | `400000` (int)  | FR-010      |
| `autoMemoryEnabled`         | `false`         | FR-013      |
| `env.MAX_MCP_OUTPUT_TOKENS` | `"10000"` (str) | FR-018      |

Never set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` in `settings.env`.

**Rationale.**

- The settings key is the lowest-precedence layer for the compaction window.
  Above it, in order, are `/autocompact`, `--autocompact <n>` and the
  environment variable. Keeping the value as a settings key leaves all three
  per-session overrides working (FR-011).
- The harness caps the window at each model's own context window, so
  200K-window models still compact at about 200K. FR-010 now says this.
- `/autocompact` normally saves to `~/.claude/settings.json`. That file is a
  read-only store symlink here, so the docs say the value applies to the
  current session only. FR-011 is reworded to match.
- The MCP output limit only moves the threshold of a built-in mechanism. Over
  the limit, the harness saves the result to `tool-results/` and shows a path
  and a preview.
- Neither kagimcp (`server.py:198,323`) nor context7-mcp 4.4.4
  (`dist/index.js:219,299`) declares `anthropic/maxResultSizeChars`, so the
  limit applies to both.
- The existing memory directories are left on disk.

**Alternatives considered.**

- The env var for the compaction window: rejected, because it outranks the
  per-session overrides.
- A per-model `modelSettings` entry: rejected, because one global value is
  enough.
- A custom PostToolUse truncation hook: rejected in clarification Q3.

## R3. Handoff-and-reset command (FR-004–009)

**Decision.**

- Add a user-only skill `bead-handoff` (frontmatter: `name`, `description`,
  `argument-hint: "[issue-id]"`, `disable-model-invocation: true`).
- Install it for Claude Code only, by adding it to the `skillsWithPlugin`
  join in `workstation/agents/skills.nix`, not to `./skills`. `./skills`
  also feeds opencode and `~/.agents/skills`, which may ignore
  `disable-model-invocation` (FR-007).
- The skill's steps:
  1. Check that a tracker exists: `bd where`. If it exits non-zero, print the
     note in the conversation and stop.
  2. Pick the issue: the `$ARGUMENTS` id, or `bd list --status in_progress
     --json --brief`. If exactly one issue is in progress, use it. If there
     are none or several, list them and ask; with none, offer `bd create`.
     Write nothing until the user answers.
  3. Append the note: `bd note <id> --stdin`, with a dated `Handoff` marker
     and labelled `Tried:`, `Failed:` and `Next:` lines, at most 20 lines.
  4. Leave the issue's status unchanged.
  5. Print `Note saved to <id>. You can now run /clear.` The skill never runs
     `/clear`.

**Rationale.**

- `bd note` appends to the notes field. `bd update --notes` replaces it, so
  the skill must never use it.
- Notes, unlike comments, appear in `bd show` and `bd list --json` without
  extra flags.
- The beads plugin's hooks (`plugins/beads/.claude-plugin/plugin.json`) run
  `bd prime` on SessionStart (including `clear`) and on PreCompact. `bd prime`
  tells the new session to list in-progress issues and `bd show` them, so the
  note is found as long as the issue stays in progress (FR-005, FR-009).
- The names `handoff` and `claude-handoff` already belong to installed
  upstream skills with other behaviour (FR-004).

**Alternatives considered.**

| Alternative                     | Why rejected                                   |
|---------------------------------|------------------------------------------------|
| Override the upstream `handoff` | Changes a skill the user may already rely on   |
| `bd comments add`               | Comments are hidden from `bd list --json`      |
| Skill runs `/clear` itself      | FR-008 forbids it; a skill cannot clear anyway |

**Measured.** `bd prime` prints 6 992 characters today. It grows with each
`bd remember`. Above 10 000 characters the harness would truncate it to a
preview; `prime.max-memory-chars` can cap it. This is not acted on now.

## R4. Instruction consistency (FR-012, FR-014, FR-015)

**Decision.**

- **FR-012 (cavecrew):**
  - Delete the "Cavecrew shortcut" section
    (`workstation/agents/subagents-docs.md:41-50`).
  - Drop `cavecrew-*` and `code-review-graph` from the agent list at
    `subagents-docs.md:14-15`, which leaves `Explore` and `Plan`.
  - Remove `{ name = "cavecrew"; }` from `workstation/agents/skills.nix:61`.
- **FR-014 (task tools):**
  - Deny the task-list tools. Put the rules in `workstation/agents/beads.nix`,
    beside the beads wiring:

    ```nix
    programs.claude-code.settings.permissions.deny = [
      "TodoWrite" "TaskCreate" "TaskGet" "TaskList" "TaskUpdate"
    ];
    ```

  - Leave `TaskStop`, `TaskOutput` and `SendMessage` allowed.
- **FR-014/015 (prose and duplication):**
  - In both `CLAUDE.md:5-59` and `AGENTS.md:342-396`, replace the bd-managed
    `BEGIN/END BEADS INTEGRATION` block with one line outside any markers,
    under the existing "Issue tracker" heading.
  - The new line reads: "Task tracking and memory: `bd` (rules come from
    `bd prime` at session start; built-in task tools are denied)."
  - `bd prime` becomes the single source of the beads workflow rules.
  - Doing the same in both files keeps the constitution's documentation
    parity.
- **Intentional duplicates:** record the remaining ones in an ADR (FR-015):
  - `bd prime` hard-codes its own "Prohibited: TodoWrite/TaskCreate" line
    (`prime.go:725,919`). It is now redundant but harmless.
  - The vendored beads skill's text contradicts the ban. It loads only when
    the skill is invoked.
  - The global git policy is stricter than bd's profile text, and it wins.

**Rationale.**

- The current task-list toolset is TaskCreate, TaskGet, TaskList and
  TaskUpdate. TodoWrite appears only with `CLAUDE_CODE_ENABLE_TASKS=0`.
- On Opus 5.x the harness does not offer these tools unless they are opted
  in, so the rule mainly covers older models and subagents.
- Denying them disables the agent teams' shared task list. Teams then
  coordinate through messages only. This trade-off is recorded in the spec
  Assumptions.
- `bd init` and `bd setup` regenerate the managed block, so a hand edit inside
  the markers would be overwritten.

**Alternatives considered.**

- Edit the ban inside the managed block: it would be lost on regeneration.
- Deny only TaskCreate: TaskList and TaskUpdate would still be offered, and
  they are useless without TaskCreate.
- Override `bd prime` with a `PRIME.md`: it would replace the whole priming
  text to remove one redundant line.

## R5. rtk banner (FR-016, FR-017)

**Decision.**

- Set `programs.claude-code.settings.env.RTK_SUPPRESS_HOOK_WARNING = "1"` in
  `workstation/agents/rtk.nix`, under its `lib.mkIf cfg.enable`.
- Leave the rewriter chain unchanged.
- Add a fast flake check that runs `${pkgs.rtk}/bin/rtk ls .` against a fake
  HOME whose `.claude/settings.json` has a non-rtk PreToolUse hook and whose
  data directory is read-only. It asserts two things:
  - **Canary:** without the variable, stderr is non-empty.
  - **Suppression:** with the variable, stderr is empty.

**Rationale.**

- rtk 1.0.1 has an official switch (`RTK_SUPPRESS_HOOK_WARNING`, or the
  config key `hooks.suppress_hook_warning`). Running the installed binary
  confirmed that it works.
- The banner appears for two reasons:
  - rtk recognises only a literal `rtk hook claude` PreToolUse command, but
    here it runs inside `agent-bash-rewriter-chain`.
  - The sandbox's read-only `~/.local/share` stops rtk's once-a-day rate
    limit from recording that it already warned.
- The canary fails the build if a future rtk version changes the warning
  path. That covers the spec's "banner text changes upstream" edge case.

**Alternatives considered.**

- Filter stderr in the chain: depends on the exact wording and hides other
  rtk errors.
- Make `~/.local/share/rtk` writable: widens the sandbox for noise.

**Out of scope.** The `home.activation` step `rtk init -g --hook-only`
(`rtk.nix:34-39`) may be dead code against a settings file that home-manager
manages. This will be filed as a follow-up bead.

## R6. Per-repository MCP loadout (FR-019)

**Decision.**

- Take `mobile-mcp` and `chrome-devtools` out of `programs.mcp.servers` for
  Claude Code.
- Build two skills-directory plugins, `hm-mobile` and `hm-browser`. Each has
  `.claude-plugin/plugin.json` with `"defaultEnabled": false` and a `.mcp.json`
  holding one server, in the shape `mkMcpServer` produces plus
  `"type": "stdio"`.
- Fold them into `skillsWithPlugin` (`skills.nix`). Also declare them
  `false` in `programs.claude-code.settings.enabledPlugins`, so the default
  is visible in the settings file.
- A repository opts in with `"enabledPlugins": {"hm-mobile@skills-dir": true}`
  in its `.claude/settings.local.json`. Local and project scope override user
  scope.
- Opencode keeps both servers: move them to an opencode-only server set.
- Update the tool prefixes quoted in
  `workstation/agents/skills/user-testing/references/drivers/*.md`, and add
  the opt-in path to the `add-mcp-server` skill.

**Rationale.**

- No user-level settings key is scoped by path, so a per-repository switch
  has to live in the target repository.
- Plugin enablement is the documented per-scope switch.
- `enabled = false` in `programs.mcp.servers` has no documented effect on
  servers bundled in a plugin.
- The repository's sandbox write-denies its own `.claude/settings*.json`, so
  the user makes the opt-in edit themselves.

**Alternatives considered.**

| Alternative                              | Why rejected                            |
|------------------------------------------|-----------------------------------------|
| `disabledMcpjsonServers` / `/mcp` toggle | Undocumented for plugin-bundled servers |
| Per-project `.mcp.json`                  | Duplicates the server definition        |
| Keep global, rely on tool search         | Instruction blocks still load           |

**Consequence.** Tool names change, for example
`mcp__plugin_hm_mobile-mcp__*` becomes `mcp__plugin_hm-mobile_mobile-mcp__*`.

## R7. Skill listing (FR-020, FR-021, SC-006)

**Decision.**

- Add the typed option `agents.skillOverrides : attrsOf (enum ["on"
  "name-only" "user-invocable-only" "off"])` and write it to
  `programs.claude-code.settings.skillOverrides`.
- Generate the entries beside each skill source: a `listing` field on
  `mkSkillEntry` (`skills.nix:25-41`). For punkt, derive the keys from
  `builtins.readDir` of the punkt input on `dig-laptop`, the only host that
  installs them.
- Values:

  | Skills                                  | Value                 | Hosts      |
  |-----------------------------------------|-----------------------|------------|
  | `understand*` (8)                       | `user-invocable-only` | all        |
  | `punkt-*` (5)                           | `user-invocable-only` | dig-laptop |
  | `spec`, `build`, `check`, `backprop`    | `name-only`           | all        |
  | `speckit-*` (project skills)            | not set (on)          | all        |

- Patch the beads marketplace source so its 29 `commands/*.md` files get
  `disable-model-invocation: true`. Reuse the sed logic from `patchSkill`,
  generalised to a single file.
- Then remove `skillListingBudgetFraction = 0.02` (`default.nix:349`) and
  update the stale comment at `skills.nix:243-248`.

**Rationale.**

- `skillOverrides` accepts exactly these four values and does not apply to
  plugin skills.
- Every group in FR-020 is a user skill. Only the beads commands are plugin
  content, and their marketplace is a Nix path, so it can be patched.
- The cavekit skills call one another (`build/SKILL.md:51,60,67`), so they
  must stay model-invocable, which means `name-only`. `skills.nix:107-113`
  already applies the same rule to mattpocock skills that other skills call.
- `speckit-*` are this repo's own project skills, and the user is using them.
- **Count.** On x13-class hosts, 8 + 4 + 29 = 41 skills and commands leave the
  description listing. On `dig-laptop` it is 46. Both exceed the SC-006
  target of 20.

**Alternatives considered.**

- `paths:` frontmatter: unverified whether it removes a skill from the
  listing.
- Patch every skill at build time: `skillOverrides` is the documented runtime
  filter.

## Refuted or unverifiable claims

| Claim                                       | Status     | Handling                   |
|---------------------------------------------|------------|----------------------------|
| A stale `rtk-rewrite.sh` hook might exist   | Refuted    | None exists; no action     |
| The machine registry has three hosts        | Refuted    | It has four; spec fixed    |
| `/autocompact` works on read-only settings  | Unverified | Quickstart check Q3        |
| Disabling auto memory keeps its directories | Unverified | Dirs are empty; harmless   |
| Project `skillOverrides` merges per key     | Unverified | Not relied on; global only |
| `paths:` hides a skill from the listing     | Unverified | Not used                   |
| Status line runs outside the sandbox        | Unverified | It reads `~/.claude` only  |

Also unverified live, and checked in the quickstart:

- The plugin cache (`installed_plugins.json` says beads 1.3.0, the marketplace
  has 1.3.1) fires `bd prime` after `/clear`.
- A plugin with `defaultEnabled: false` stays disconnected until a project
  opts in.
- A patched plugin with an unchanged version is copied into the cache again.
  It may need a version suffix.
