# Tasks: Agent Context Hygiene

**Input**: Design documents from `specs/007-context-hygiene/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/, quickstart.md

**Tests**: The spec asks for no TDD. Two fast flake checks are still
included, because constitution Principles I and III require them. They are
`context-statusline` (US1) and `rtk-banner` (US5).

**Organization**: Tasks are grouped by user story, so each story can be
implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel: different files, and no dependency on an
  unfinished task.
- **[Story]**: the user story the task belongs to (US1–US7).

## Rules for every task

- The flake sees only git-tracked files. `git add` every new file before
  `nix build` or `nix flake check`.
- Write each new shell script with `writeShellApplication`, and refer to
  executables with `lib.getExe` or `${pkg}/bin/...`.
- An assertion message MUST name its file and the fix. Follow
  `workstation/agents/process-cap.nix:255-271`.
- The agent's sandbox blocks writes to `.claude/skills/**` and
  `.claude/settings*.json`. Tasks marked **(user edit)** need the user to
  approve or make the change.
- Never `git commit`. Stage the changes and report them.

---

## Phase 1: Setup

**Purpose**: record the baseline that SC-006 compares against, and track the
work in beads.

- [X] T001 Create one beads epic, "Agent context hygiene (specs/007)", and one
  child task per user story, US1–US7. Use
  `bd create --type=epic|task --parent=<epic>` and put the spec path in each
  description. Do not use a markdown TODO list.
- [X] T002 Record the 2026-10-27 baseline in
  `specs/007-context-hygiene/baseline.md`. Take it on dig-laptop, the SC-006
  baseline host; abort if `hostname` is not dig-laptop. Record:
  - the number of `programs.mcp.servers` entries in
    `workstation/agents/mcp-servers.nix` (9 today)
  - **Described-skill count, for each host** `<h>` in `work-laptop`,
    `desktop`, `laptop` and `dig-laptop`:
    1. Build `nixosConfigurations.<h>`.
    2. Count the built home-files `.claude/skills/*/SKILL.md` that lack
       `disable-model-invocation: true` and have no `skillOverrides` key
       (`user-invocable-only`, `name-only` or `off`).
    3. Add the beads `plugins/beads/skills/beads/commands/*.md` files that
       lack the key.
  - For dig-laptop only, also the count from a fresh session's skill
    listing
  - the `bd prime | wc -c` size (6992 today)

---

## Phase 2: Foundational (blocks US1 and US3)

**Purpose**: the `agents.context` option namespace, which both the status
line and the compaction point read.

- [ ] T003 Create `workstation/agents/statusline.nix`, a module taking
  `{ inputs, lib, pkgs, config, ... }`.
  - Declare these options:
    - `agents.context.statusLine.enable` (`lib.types.bool`, default `true`)
    - `agents.context.warnTokens` (`lib.types.ints.positive`, default
      `200000`)
    - `agents.context.strongTokens` (`lib.types.ints.positive`, default
      `400000`)
    - `agents.context.autoCompactTokens`
      (`lib.types.ints.between 100000 1000000`, default `400000`)
  - Add `assertions` for `warnTokens < strongTokens` and
    `autoCompactTokens >= strongTokens`. Each message names
    `workstation/agents/statusline.nix` and the fix.
  - Leave `config` otherwise empty for now.
- [ ] T004 Add `./statusline.nix` to the `imports` list in
  `workstation/agents/default.nix` (lines 309-323, alphabetical, after
  `./skills.nix`). Then `git add workstation/agents/statusline.nix` and run
  `nix flake check`. It must pass.

**Checkpoint**: the options evaluate. Setting `warnTokens = 500000` makes
evaluation fail with the T003 message.

---

## Phase 3: User Story 1 – See how large the context has grown (P1) 🎯 MVP

**Goal**: the status line shows the caveman badge, when one is active, plus
the context size, styled at the 200K and 400K points (FR-001, FR-002,
FR-003).

**Independent test**: `nix flake check` passes `context-statusline`. After
deploying, quickstart check Q1 shows a dim size after the first prompt.

- [ ] T005 [P] [US1] Create `workstation/agents/packages/context-statusline.nix`,
  a callPackage function.
  - **Signature:** `{ writeShellApplication, jq, coreutils, gnugrep, gnused,
    bash, warnTokens, strongTokens, cavemanScript ? null }`. It returns a
    `writeShellApplication` named `context-statusline` with runtimeInputs
    `[ jq coreutils gnugrep gnused bash ]`. The upstream caveman script
    calls grep, sed, head and tr.
  - **Behaviour**, per `specs/007-context-hygiene/contracts/statusline.md`:
    1. Read stdin once into a variable (`input=$(cat)`).
    2. If `cavemanScript` is not null, get the badge with
       `badge=$(bash <script> <<<"$input" || true)`.
    3. Compute the size with one jq call taking
       `--argjson warn/strong`: `.context_window.total_input_tokens`.
       Treat missing, null, non-number or `0` as no data.
    4. Format the size:
       - `t < 1000000`: `\(t/1000|round)K`.
       - `t >= 1000000`: let `d = (t/100000|floor)`, truncated, not
         rounded. Print `\(d/10|floor).\(d%10)M`, so 1250000 gives `1.2M`
         and 1000000 gives `1.0M`.
    5. Style it with SGR `2` when `t <= warn`, `33` when
       `warn < t <= strong`, and `1;37;41` when `t > strong`. End each styled
       segment with `\033[0m`. Use strict `>` comparisons.
    6. Print the badge, then a space only when both segments are non-empty,
       then the size. Print no trailing newline. Always `exit 0`.
  - Guard every command that can fail with `|| true`. writeShellApplication
    turns on errexit, nounset and pipefail.
- [ ] T006 [US1] In `workstation/agents/statusline.nix`, under
  `lib.mkIf cfg.statusLine.enable`, call the T005 package with
  `pkgs.callPackage ./packages/context-statusline.nix { ... }`.
  - Pass `warnTokens`/`strongTokens` from `config.agents.context`.
  - Pass `cavemanScript = if config.agents.tools.caveman.enable then
    "${inputs.caveman}/src/hooks/caveman-statusline.sh" else null`.
  - Set `programs.claude-code.settings.statusLine = { type = "command";
    command = lib.getExe <pkg>; }`.
- [ ] T007 [US1] Remove the `settings.statusLine` attribute from
  `workstation/agents/caveman.nix` (lines 74-79). Keep `hooksDir` and the
  rest of the `lib.mkIf cfg.enable` block. Without this, two modules define
  `statusLine` and evaluation fails.
- [ ] T008 [P] [US1] Create `tests/context-statusline.nix`, a `runCommand`
  check in the style of `tests/agent-commit-gate.nix`.
  - Build the T005 package with `warnTokens = 200000`,
    `strongTokens = 400000`, and `cavemanScript` set to the caveman input's
    script. Take it as a function argument, `caveman-src`.
  - Set `HOME=$TMPDIR/home` and create `$HOME/.claude/.caveman-active`
    containing `full`.
  - For each input, assert the exact stdout bytes and exit code 0:
    - `{}`, `null`, `{"context_window":{"total_input_tokens":0}}` and the
      text `garbage`: badge only
    - `38211`: dim `38K`
    - `200000`: dim `200K`
    - `200001`: yellow `200K`
    - `412000`: bold-red `412K`
    - `1250000`: bold-red `1.2M`
    - `1000000`: bold-red `1.0M`
  - Also run one case with `cavemanScript = null` and `38211`: dim `38K`, no
    leading space.
  - Also run one case with `cavemanScript` set to a script that runs
    `exit 1`, and `38211`: dim `38K`, no leading space, exit code 0.
- [ ] T009 [US1] Register the check in `flake.nix` `checks` (around lines
  389-401), next to `agent-commit-gate`, with a one-line comment
  `# The context status line; see the file.`:
  `context-statusline = nixpkgsFor.${system}.callPackage ./tests/context-statusline.nix { caveman-src = inputs.caveman; };`.
- [ ] T010 [US1] `git add` the new files and run `nix flake check` and
  `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`.
  `jq .statusLine` on the generated `settings.json` shows
  `type = "command"` and the store path of `context-statusline`.

**Checkpoint**: US1 is shippable on its own.

---

## Phase 4: User Story 2 – Hand off work and reset (P1)

**Goal**: `/bead-handoff` appends a tried/failed/next note to the
in-progress bead, then tells the user to `/clear` (FR-004 to FR-009).

**Independent test**: the quickstart "Handoff round trip".

- [ ] T011 [P] [US2] Create
  `workstation/agents/skills-claude-only/bead-handoff/SKILL.md`, exactly per
  `specs/007-context-hygiene/contracts/bead-handoff.md`.
  - Frontmatter: `name: bead-handoff`, the `description`,
    `argument-hint: "[issue-id]"`, `disable-model-invocation: true`.
  - Steps:
    1. Run `bd where`. If it exits non-zero, print the note in the
       conversation and stop.
    2. Pick the issue with
       `bd list --status in_progress --json --brief`. Use the
       `$ARGUMENTS` id first. With 0 or more than 1 issue, ask and write
       nothing.
    3. Run `bd note <id> --stdin` with the body
       `Handoff YYYY-MM-DD` / `Tried:` / `Failed:` / `Next:`, at most 20
       lines.
    4. Print `Note saved to <id>. You can now run /clear.`
  - Say explicitly: never run `bd update --notes`, `bd close`,
    `bd update --status` or `/clear`.
- [ ] T012 [US2] In `workstation/agents/skills.nix`, add
  `./skills-claude-only` to the `paths` of `skillsWithPlugin` (the `paths`
  list at lines 284-292, after the `claude-code-hm-plugin-skill` linkFarm),
  with a comment. These skills go to `~/.claude/skills` only. They are
  not in `mergedSkills`, so opencode and `~/.agents/skills` do not get a
  skill that might be auto-invoked (FR-007).
- [ ] T013 [US2] Check that `bd note` appends rather than replaces, using a
  scratch bead:
  1. `bd create --title="note append probe" --type=task`
  2. Run `bd note <id> --stdin` twice with different text.
  3. `bd show <id>` must show both notes.
  4. `bd close <id>`.

  If it replaces, stop and report: `contracts/bead-handoff.md` would need
  another append method.
- [ ] T014 [US2] `git add` the skill, then build the home configuration. The
  generated `.claude/skills/bead-handoff/SKILL.md` must exist, and must be
  absent from `.config/opencode/skills` and `.agents/skills`.

**Checkpoint**: US1 and US2, the P1 MVP, both work.

---

## Phase 5: User Story 5 – Stop noise in every tool result (P2)

**Goal**: no `No hook installed` banner in shell results, and compression
still on (FR-016, FR-017).

**Independent test**: `nix flake check` passes `rtk-banner`; quickstart
check Q2.

- [ ] T015 [P] [US5] In `workstation/agents/rtk.nix`, add
  `programs.claude-code.settings.env.RTK_SUPPRESS_HOOK_WARNING = "1";` under
  `lib.mkIf cfg.enable`. Bind the variable name in a `let` (for example
  `suppressVar`). Add a comment giving the cause: rtk recognises only its own
  `rtk hook claude` command, and the sandbox's read-only `~/.local/share`
  defeats its daily rate limit. Do not widen the sandbox.
- [ ] T016 [P] [US5] Create `tests/rtk-banner.nix`, a `runCommand` taking
  `rtk` as an explicit argument. `flake.nix` passes in an rtk evaluated with
  the repo's unfree predicate, because rtk is BUSL-1.1 (unfree).
  - Set up a fake HOME:
    - `.claude/settings.json` has one PreToolUse hook whose command is
      `true`.
    - `.local/share` is made read-only.
  - Point `XDG_DATA_HOME` and `XDG_CONFIG_HOME` inside it.
  - Run `rtk ls .` twice and assert:
    - **Canary:** without the variable, stderr is non-empty. This proves the
      warning path still exists.
    - **Suppression:** with `RTK_SUPPRESS_HOOK_WARNING=1`, stderr is empty
      and stdout is non-empty.
- [ ] T017 [US5] Register the check in `flake.nix` `checks`:
  `rtk-banner = nixpkgsFor.${system}.callPackage ./tests/rtk-banner.nix { rtk = (import nixpkgs { inherit system; config.allowUnfreePredicate = import ./common/unfree-predicates.nix { inherit (nixpkgs) lib; }; }).rtk; };`.
  Comment: "rtk is unfree (BUSL-1.1); `nixpkgsFor` has no unfree predicate".
  First check how `common/unfree-predicates.nix` is called elsewhere in
  `flake.nix`, and match that call. This task comes after T009, because both edit `flake.nix`.
- [ ] T018 [US5] `git add`, then run `nix flake check`. The generated
  settings show `env.RTK_SUPPRESS_HOOK_WARNING = "1"`.

---

## Phase 6: User Story 3 – Cap context growth before summarization (P2)

**Goal**: automatic summarization at 400K, or the model's window if that is
smaller; per-session overrides still win (FR-010, FR-011).

**Independent test**: generated `settings.json` has
`autoCompactWindow = 400000` and no `CLAUDE_CODE_AUTO_COMPACT_WINDOW` in
`env`. Quickstart check Q3.

- [ ] T019 [US3] In `workstation/agents/statusline.nix`, set
  `programs.claude-code.settings.autoCompactWindow =
  cfg.autoCompactTokens;` as a plain integer. Do not put it under
  `lib.mkIf cfg.statusLine.enable`.
  - Add a comment saying why this is a settings key and not the env var:
    the env var outranks `/autocompact` and `--autocompact`, which would
    break FR-011.
  - Depends on T003.
- [ ] T020 [US3] Build, then
  `jq '.autoCompactWindow, .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW'` on the
  generated settings. Expected output: `400000` and `null`.

---

## Phase 7: User Story 4 – Remove contradicting instructions (P2)

**Goal**: no instruction names a missing agent; one memory store; the task
tools denied by a rule; beads rules from one source (FR-012 to FR-015).

**Independent test**: US4 acceptance scenarios 1–4; quickstart check Q8.

- [ ] T021 [P] [US4] In `workstation/agents/subagents-docs.md`:
  - Delete the "Cavecrew shortcut" section (lines 41-50).
  - In the specialised-agent list (lines 14-15), remove `cavecrew-*` and
    `code-review-graph`, leaving `Explore` and `Plan`.
- [ ] T022 [P] [US4] In `workstation/agents/skills.nix`, delete
  `{ name = "cavecrew"; }` from `cavemanSkillsSubset` (line 61).
- [ ] T023 [P] [US4] In `workstation/agents/beads.nix`, add
  `programs.claude-code.settings.permissions.deny = [ "TodoWrite"
  "TaskCreate" "TaskGet" "TaskList" "TaskUpdate" ];`.
  - Add a comment: beads is the tracker. On Opus 5.x these tools are not
    offered anyway. The deny also turns off the agent-teams shared task
    list, which is accepted (see the spec Assumptions).
  - Do NOT deny `TaskStop`, `TaskOutput` or `SendMessage`.
- [ ] T024 [P] [US4] In `workstation/agents/default.nix`, next to the other
  scalar settings (around line 346), add
  `programs.claude-code.settings.autoMemoryEnabled = false;`, with a comment
  naming `bd remember` as the single memory store.
- [ ] T025 [US4] In `CLAUDE.md`, delete lines 5-59: the whole
  `<!-- BEGIN BEADS INTEGRATION ... -->` … `<!-- END BEADS INTEGRATION -->`
  block, markers included.
  - Under the existing `### Issue tracker` heading (around line 110), add
    one line outside any marker: ``Task tracking and memory: `bd` (rules come
    from `bd prime` at session start; built-in task tools are denied).``
  - In `docs/agents/issue-tracker.md` (line 5), replace the
    TodoWrite/TaskCreate sentence with: "Built-in task tools are denied by
    settings; use `bd`."
  - **(user edit)** if the sandbox refuses the write.
- [ ] T026 [US4] Make the same change in `AGENTS.md`. Delete the
  `BEGIN/END BEADS INTEGRATION` block (lines 342-396), and add the same
  one-line pointer under `### Issue tracker` (around line 400).
  - Leave the `BEADS CODEX SETUP` block (lines 412-434) alone. Codex gets no
    `bd prime` hook.
  - The constitution requires parity with CLAUDE.md. Depends on T025.
- [ ] T027 [US4] Build. In the generated settings:
  - `jq '.permissions.deny'` contains the five task tools, and none of
    `TaskStop`, `TaskOutput`, `SendMessage`.
  - `jq '.autoMemoryEnabled'` gives `false`.
  - The generated `.claude/skills/cavecrew` is absent.
  - `grep -rn cavecrew workstation/` returns nothing.

---

## Phase 8: User Story 7 – Bound the size of tool-server results (P3)

**Goal**: MCP text results over 10K tokens are saved to a file and replaced
by a preview (FR-018, SC-007).

**Independent test**: generated `env.MAX_MCP_OUTPUT_TOKENS = "10000"`;
quickstart check Q7.

- [ ] T028 [US7] In `workstation/agents/mcp-servers.nix`:
  - Declare `options.agents.mcp.optIn.outputTokens`
    (`lib.types.ints.between 1000 100000`, default `10000`).
  - Bind `cfg = config.agents.mcp.optIn;` in the file's `let`.
  - Set `programs.claude-code.settings.env.MAX_MCP_OUTPUT_TOKENS =
    toString cfg.outputTokens;`.
  - Comment: the harness saves larger results to `tool-results/` and shows
    a path and a preview. kagimcp and context7-mcp 4.4.4 declare no
    `anthropic/maxResultSizeChars` (re-check on a version bump). Grep every
    other MCP server's package for `maxResultSizeChars` too, and list in the
    comment each server that declares it, or "none". This covers US7
    scenario 4.
  - The file has no `options`/`config` split today, so add one.
- [ ] T029 [US7] Build. `jq '.env.MAX_MCP_OUTPUT_TOKENS'` gives `"10000"`.

---

## Phase 9: User Story 6 – Load only relevant tools and skills (P3)

**Goal**: `mobile-mcp` and `chrome-devtools` are off by default and enabled
per repository. Domain skills leave the automatic listing, and the budget
returns to 0.01 (FR-019, FR-020, FR-021, SC-006).

**Independent test**: US6 acceptance scenarios 1–6; quickstart checks Q4,
Q5, Q6 and "Per-repository opt-in".

### Tool-server loadout (FR-019)

- [ ] T030 [US6] In `workstation/agents/mcp-servers.nix`, declare
  `options.agents.mcp.optIn.servers` (`lib.types.listOf (lib.types.enum [
  "mobile-mcp" "chrome-devtools" ])`, default both).
  - Move the `mobile-mcp` and `chrome-devtools` `mkMcpServer` definitions
    into a `let`-bound attrset, `optInServers`.
  - `programs.mcp.servers` gets every server except those in
    `cfg.servers`.
  - Depends on T028, which edits the same file.
- [ ] T031 [US6] In the same file, build one plugin directory per opt-in
  server with `pkgs.runCommand`:
  - Define in the `let`: `pluginNames = { "mobile-mcp" = "hm-mobile";
    "chrome-devtools" = "hm-browser"; };` and `pluginName = s:
    pluginNames.${s};`. Use them for the directory names, the
    `plugin.json` `name`, the `agents.claudeSkillsDirPlugins` keys, and
    T033.
  - Each contains `.claude-plugin/plugin.json`, for example
    `{"name":"hm-browser","version":"1.0.0","description":"chrome-devtools MCP (opt-in per repo)","defaultEnabled":false}`.
  - Each also contains `.mcp.json`:
    `{"mcpServers":{"<server>":{"type":"stdio","command":...,"args":[...]}}}`,
    where `command` and `args` come from the `optInServers` entry, so
    caveman-shrink wrapping is kept.
  - Expose the directories through a new internal option,
    `agents.claudeSkillsDirPlugins` (`attrsOf package`, `internal = true`).
    It maps each plugin name to its directory, which `linkFarm` accepts
    as is.
  - Per `specs/007-context-hygiene/contracts/mcp-opt-in.md`.
- [ ] T032 [US6] In `workstation/agents/skills.nix`, add
  `(pkgs.linkFarm "claude-opt-in-plugins" config.agents.claudeSkillsDirPlugins)`
  to `skillsWithPlugin` `paths`, next to `./skills-claude-only` from T012.
  Keep the plugin names `hm-mobile` and `hm-browser` distinct from every
  skill name.
- [ ] T033 [US6] Make the default visible in `workstation/agents/mcp-servers.nix`:
  `programs.claude-code.settings.enabledPlugins = lib.genAttrs (map (s:
  "${pluginName s}@skills-dir") cfg.servers) (_: false);`. It merges
  with `default.nix`'s `enabledPlugins`.
- [ ] T034 [US6] Keep opencode unchanged. In `workstation/agents/mcp-servers.nix`,
  add each `optInServers` entry to `programs.opencode.settings.mcp.<name>`
  in opencode's local-server shape:
  `{ type = "local"; command = [ command ] ++ args; enabled = true; }`.
  Then confirm that the generated `opencode.json` still lists both servers.
- [ ] T035 [P] [US6] Update the quoted tool prefixes:
  - In `workstation/agents/skills/user-testing/references/drivers/mobile.md`,
    `mcp__plugin_hm_mobile-mcp__` becomes
    `mcp__plugin_hm-mobile_mobile-mcp__`.
  - In `workstation/agents/skills/user-testing/references/drivers/chrome-devtools.md`,
    `mcp__plugin_hm_chrome-devtools__` becomes
    `mcp__plugin_hm-browser_chrome-devtools__`.
  - Add one line to each: it needs
    `enabledPlugins."hm-<x>@skills-dir": true` in the repository's
    `.claude/settings.local.json`.
- [ ] T036 [P] [US6] **(user edit)** In `.claude/skills/add-mcp-server/SKILL.md`,
  document the opt-in path: add the server to `agents.mcp.optIn.servers`'s
  enum, plus a plugin name, instead of `programs.mcp.servers`. The sandbox
  denies agent writes to `.claude/skills`. Prepare the diff and ask the user
  to apply it.

### Skill listing (FR-020, FR-021)

- [ ] T037 [US6] In `workstation/agents/skills.nix`:
  - Declare `options.agents.skillOverrides` (`lib.types.attrsOf
    (lib.types.enum [ "on" "name-only" "user-invocable-only" "off" ])`,
    default `{ }`), and set `programs.claude-code.settings.skillOverrides =
    config.agents.skillOverrides;`.
  - Add `listing ? null` to the inner argument pattern of `mkSkillEntry`
    (lines 30-34). Do not pass it into the returned `{ name; path; }`.
  - Hoist the `cavekitSkills` and `understandAnythingSkills` record lists
    into `let` bindings, `cavekitRecords` and `understandRecords`.
  - Compute:

    ```nix
    listingOverrides = lib.listToAttrs (map (r: lib.nameValuePair r.name r.listing)
      (builtins.filter (r: (r.listing or null) != null)
        (cavekitRecords ++ understandRecords)));
    ```

  - Set `agents.skillOverrides = listingOverrides;` in `config`.
- [ ] T038 [US6] Set `listing` on the records in `workstation/agents/skills.nix`:
  - `"user-invocable-only"` on all 8 `understandAnythingSkills` entries
    (lines 207-214).
  - `"name-only"` on the `cavekitSkills` entries `backprop`, `build`,
    `check` and `spec`.
  - Comment: `build/SKILL.md` invokes `backprop` and `spec`, so they must
    stay model-invocable. This is the same rule as lines 107-113.
  - Do not touch `speckit-*`. They are project skills of this repo.
- [ ] T039 [P] [US6] In `machines/dig-laptop/default.nix`, set
  `home-manager.users.${config.user.username}.agents.skillOverrides` from
  `lib.mapAttrs (_: _: "user-invocable-only") (lib.filterAttrs (_: t: t ==
  "directory") (builtins.readDir "${inputs.punkt-skills}/skills"))`, so skills
  added upstream are covered without listing them by hand. Add `lib` to the
  module arguments; today they are only `{ config, inputs, pkgs, ... }`. Five
  directories exist today.
- [ ] T040 [US6] In `workstation/agents/beads.nix`, replace
  `programs.claude-code.marketplaces.beads-marketplace =
  pkgs.nvSources.beads.src;` with a `pkgs.runCommand` copy of that source.
  - Insert `disable-model-invocation: true` into the frontmatter of every
    `plugins/beads/skills/beads/commands/*.md` (29 files). Use the
    `patchSkill` sed from `skills.nix:11-21`, generalised to a single file
    path. Skip files that already have the key. If a file's first line is
    not `---` (`prime.md`, `template.md`), prepend
    `---\ndisable-model-invocation: true\n---\n`. Run `chmod -R u+w $out`
    after `cp -r`, because the source files are read-only.
  - Assert at build time that all 29 files contain the key.
  - Suffix the plugin version in
    `plugins/beads/.claude-plugin/plugin.json` (for example `1.3.1+hm1`),
    so Claude Code re-caches it. The research found this risk. Apply the
    same suffix to `.plugins[0].version` in `.claude-plugin/marketplace.json`
    (`jq '.plugins[0].version += "+hm1"'`), so the two versions agree.
  - Leave the `beads:beads` skill itself unchanged.
- [ ] T041 [US6] Remove
  `programs.claude-code.settings.skillListingBudgetFraction = 0.02;` from
  `workstation/agents/default.nix` (line 349), so the harness default 0.01
  applies. Update the stale comment at `workstation/agents/skills.nix:243-248`:
  - It says `0.02`.
  - It says `CLAUDE_SKILL_FILTER` does not exist. Name `skillOverrides` as the
    runtime filter instead.
- [ ] T042 [US6] Build every host:
  - `nix build ".#nixosConfigurations.<h>.config.system.build.toplevel"`
    for `work-laptop`, `desktop`, `laptop` and `dig-laptop`.
  - The generated settings match
    `specs/007-context-hygiene/contracts/deployed-settings.md` (enabledPlugins
    `hm-*` false, `skillOverrides`, no `skillListingBudgetFraction`).
  - `.claude/skills/hm-browser/.mcp.json` exists.
  - The generated `opencode.json` still has both servers.

---

## Phase 10: Polish & Cross-Cutting

- [ ] T043 [P] Write `docs/adr/0008-agent-context-hygiene.md` in the format
  of `docs/adr/0006-agent-commit-gate.md`. Record:
  - the single memory store (`bd remember`; auto memory off)
  - the reset workflow (`/bead-handoff` + `/clear` + `bd prime`)
  - per-repository opt-in servers as default-off skills-dir plugins
  - the task-tool deny and its agent-teams cost
  - the intentional duplicates kept under FR-015:
    - the hard-coded `bd prime` "Prohibited" line
    - the vendored beads skill text that contradicts the ban
    - the global git policy, which overrides bd's profile text
  - the risk that `bd init` re-adds the CLAUDE.md block
- [ ] T044 [P] Add a `### Agents / context` section to `GLOSSARY.md`, after
  the `### Agents / sandbox` section, immediately before `### Emacs / beads`
  (line 184). Define **Context size**,
  **Warning point**, **Summarization point**, **Handoff note** and
  **Tool-server loadout**, using the definitions in `spec.md` Key Entities.
- [ ] T045 [P] File follow-up beads, linked to the T001 epic:
  - `rtk.nix` `home.activation.rtkHook` may be dead code.
  - Cap `bd prime` with `prime.max-memory-chars` before it reaches 10 000
    characters.
  - Opencode per-project MCP loadout parity.
  - The host list in `CLAUDE.md`/`AGENTS.md` names `x13-laptop`, but the
    registry has `laptop`.
  - The rtk tracking DB cannot be written inside the sandbox.
  - Periodic review or expiry of `bd remember` memories (strategic
    forgetting). Check whether bd supports expiry.
- [ ] T046 Run `nix fmt` and revert unrelated formatting churn
  (`git diff --stat` must list only this feature's files). Then run
  `nix flake check`. It must pass with `context-statusline` and
  `rtk-banner`.
  - Then evaluate each invalid value from the quickstart "Also try invalid
    values" list, plus `agents.mcp.optIn.servers = [ "github-mcp" ]` and
    `agents.mcp.optIn.outputTokens = 0`. Each must fail evaluation with a
    message naming its file.
- [ ] T047 Re-run the T002 build-derived measurements for every host and
  append them to `specs/007-context-hygiene/baseline.md`. On every host,
  SC-006 needs at least 2 fewer MCP servers and at least 20 fewer described
  skills or commands. The live-session count is taken in T048. Stage every changed file with `git add`, list them for the user,
  and do not commit.
- [ ] T048 **(user, after `sudo nixos-rebuild switch --flake .#<host>`)** Run
  `specs/007-context-hygiene/quickstart.md` checks Q1–Q8, the handoff round
  trip and the per-repository opt-in, and record the results in the matching
  bead. Also:
  - Record the dig-laptop live-session skill count in `baseline.md`.
  - Run `/doctor prompt-audit` once. Every beads rule it reports as
    duplicated must appear in the ADR 0008 list of intentional duplicates,
    or the duplicate must be removed. Close the beads whose checks pass.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T002)**: no dependencies.
- **Foundational (T003–T004)**: blocks US1 and US3 only.
- **US1 (P1)**: after Foundational.
- **US2 (P1)**: independent; can start right after Setup. T012 edits
  `skills.nix`.
- **US5 (P2)**: independent. T017 follows T009 (`flake.nix`).
- **US3 (P2)**: after T003. T019 edits `statusline.nix`, so it runs after
  T006.
- **US4 (P2)**: independent. T022 edits `skills.nix`, so it runs after T012.
  T026 follows T025.
- **US7 (P3)**: independent; first edit of `mcp-servers.nix`.
- **US6 (P3)**: after US7 (T030 follows T028 in `mcp-servers.nix`) and after
  US2/US4 (shared `skills.nix`: T032 and T037 follow T012 and T022). T040
  follows T023 (`beads.nix`). T041 follows T024 (`default.nix`).
- **Polish**: after all the stories you are shipping.

### Same-file chains (never parallel)

| File                                 | Order                                   |
|--------------------------------------|-----------------------------------------|
| `workstation/agents/statusline.nix`  | T003 → T006 → T019                      |
| `workstation/agents/skills.nix`      | T012 → T022 → T032 → T037 → T038 → T041 |
| `workstation/agents/mcp-servers.nix` | T028 → T030 → T031 → T033 → T034        |
| `workstation/agents/beads.nix`       | T023 → T040                             |
| `workstation/agents/default.nix`     | T004 → T024 → T041                      |
| `flake.nix`                          | T009 → T017                             |
| `CLAUDE.md`, `AGENTS.md`             | T025 → T026                             |

## Parallel Examples

**After Foundational, start these together** (all different files):

```text
T005 [US1] workstation/agents/packages/context-statusline.nix
T008 [US1] tests/context-statusline.nix
T011 [US2] workstation/agents/skills-claude-only/bead-handoff/SKILL.md
T015 [US5] workstation/agents/rtk.nix
T016 [US5] tests/rtk-banner.nix
T021 [US4] workstation/agents/subagents-docs.md
T023 [US4] workstation/agents/beads.nix
```

**US6 docs, alongside its Nix work:**

```text
T035 [US6] user-testing driver docs
T036 [US6] add-mcp-server SKILL.md (user edit)
T039 [US6] machines/dig-laptop/default.nix
```

**Polish:** T043, T044 and T045 can run in parallel.

## Implementation Strategy

### MVP (P1): US1 + US2

1. Setup, then Foundational.
2. US1: the status line. Validate it with `nix flake check`
   (`context-statusline`).
3. US2: `/bead-handoff`. Validate it with the quickstart round trip.
4. **Stop.** Deploy and run quickstart Q1 and the handoff round trip. Those
   two together give the "notice, then reset" loop that the research
   identified as the main remedy.

### Incremental

1. **P2 batch:** US5, then US3, then US4. Each is a small settings change
   with its own build check.
2. **P3 batch:** US7, then US6. US6 is the largest change: plugins,
   overrides, the beads patch and the budget. Run `/doctor` before and after,
   and ship it last.
3. **Polish:** the ADR, GLOSSARY entries, follow-up beads, and the SC-006
   re-measure.
