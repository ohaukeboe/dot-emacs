# Custom SDD skills: mattpocock/skills and Spec Kit in one workflow

Research report. Question: what do Matt Pocock's skills and GitHub Spec Kit
each read and write in a project, where do they overlap or collide, and what
custom skill set would keep the repo clean and let both cooperate?

Checked on 2026-11-06 against:

- `mattpocock/skills` at `4ae2317` (the `mattpocock-skills` pin in
  `flake.lock`), read from the Nix store copy of that rev [mp]
- `github/spec-kit` tag `v1.0.6` = `96c9bd6` [sk], the version recorded in
  this repo's `.specify/init-options.json`, plus the rendered skills in
  `.claude/skills/speckit-*`
- the Claude Code docs pages on memory and skills [cc-mem] [cc-skills]
- this repo at `e473888` as a worked example of both toolkits

Paths below are relative to the repo they belong to: `mp:` = mattpocock
repo, `sk:` = spec-kit repo, bare paths = this repo.

## TL;DR

- Most mattpocock skills write **nothing** to the repo by default.
  `improve-codebase-architecture` and `handoff` write to `$TMPDIR`. Only three
  things write into the repo: `domain-modeling` (`GLOSSARY.md`,
  `docs/adr/`), the issue tracker when it is local markdown (`.scratch/`),
  and `setup-matt-pocock-skills`. The setup skill writes the clutter you
  dislike: `docs/agents/{issue-tracker,domain,triage-labels}.md` plus an
  `## Agent skills` block in `CLAUDE.md`.
- `docs/agents/*.md` is only a way to get "which tracker, which labels,
  where the glossary is" into context. The skills never read those files by
  path. They say the config "should have been provided to you"
  (`mp:skills/engineering/to-spec/SKILL.md`), and the `CLAUDE.md` pointer
  block puts it there. So any context source works: a user-level rule in
  `~/.claude/rules/`, `CLAUDE.local.md`, or text in the skill itself.
- Spec Kit is vendored per project by design: `.specify/` (scripts,
  templates, constitution) and `.claude/skills/speckit-*`. It writes
  `specs/NNN-slug/*`. In v1.0.x it no longer touches `CLAUDE.md` or creates
  branches unless you opt into the bundled `agent-context` and `git`
  extensions.
- The real conflicts are semantic, not path collisions. Both have a "spec",
  a "task graph", a "clarify" interview and a "decision record", and neither
  knows the other's copy exists. The one physical collision is
  `implement-spec`/`to-tickets`, which want an issue tracker, and Spec Kit,
  which keeps the task graph in `tasks.md`.
- Recommendation: (1) stop running `setup-matt-pocock-skills`. Move its
  generic content into one Nix-managed user rule (`programs.claude-code.rules`)
  that also states the "speckit mode" contract. (2) Fork only four skills
  (`to-spec`, `to-tickets`, `implement-spec`, `grill-with-docs`) into
  `workstation/agents/skills/`, each with a `.specify/` branch that writes
  into `specs/<feature>/` instead of the tracker. (3) Keep `GLOSSARY.md` and
  `docs/adr/` as the only mattpocock artifacts in repos.

## 1. mattpocock skills: what they read and write

All at rev `4ae2317`. "Reads" means that if the file exists the skill uses
it, and if it is missing the skill carries on silently. The repo's ADR 0001
splits skills into hard- and soft-dependency ones
(`mp:.agents/adr/0001-explicit-setup-pointer-only-for-hard-dependencies.md`).

| Skill                         | Reads in repo               | Writes in repo           |
| ----------------------------- | --------------------------- | ------------------------ |
| grill-with-docs               | via its two callees         | via domain-modeling      |
| grilling                      | code (via subagents)        | nothing                  |
| domain-modeling               | GLOSSARY(-MAP), docs/adr/   | GLOSSARY.md, docs/adr/   |
| improve-codebase-architecture | git log, GLOSSARY, ADRs     | via domain-modeling only |
| codebase-design               | nothing specific            | nothing                  |
| to-spec                       | GLOSSARY, ADRs; tracker cfg | tracker (hard dep)       |
| to-tickets                    | spec ref; tracker cfg       | tracker (hard dep)       |
| implement-spec                | spec + tickets; tracker cfg | worktrees, code          |
| implement                     | ticket from tracker         | code                     |
| tdd                           | GLOSSARY, ADRs              | tests, code              |
| diagnosing-bugs               | GLOSSARY, ADRs              | tests, code; no docs     |
| research                      | existing notes convention   | one Markdown file        |
| code-review                   | spec: docs/ specs/ .scratch | nothing                  |
| triage                        | tracker, .out-of-scope/     | tracker, .out-of-scope/  |
| setup-matt-pocock-skills      | remote, CLAUDE.md, ...      | docs/agents/*, CLAUDE.md |
| handoff                       | nothing                     | `$TMPDIR` only           |

Sources: each row's `SKILL.md` under `mp:skills/engineering/<name>/` or
`mp:skills/productivity/<name>/`. Details that matter:

- **grill-with-docs** is two lines: "Call the Skill tool twice, for
  "grilling" and "domain-modeling"." The grilling part never writes. The
  domain-modeling part writes `GLOSSARY.md` "inline" as terms resolve, and
  offers an ADR only when a decision is hard to reverse, surprising and a
  real trade-off. Files are created lazily
  (`mp:skills/engineering/domain-modeling/SKILL.md`, `ADR-FORMAT.md`,
  `GLOSSARY-FORMAT.md`).
- **ADR numbering** is "scan `docs/adr/` for the highest existing number and
  increment by one" (`ADR-FORMAT.md`). Parallel branches therefore collide.
  This repo already has two `0007-*` and two `0009-*` ADRs in `docs/adr/`.
- **improve-codebase-architecture** writes its HTML report to
  `<tmpdir>/architecture-review-<timestamp>.html` "so nothing lands in the
  repo". It writes to the repo only through `domain-modeling`.
- **to-spec** has no template file. The template is inline in `SKILL.md`
  (Problem, Solution, User Stories, Implementation Decisions, Testing
  Decisions, Out of Scope). The skill publishes to the tracker with label
  `ready-for-agent`.
- **to-tickets** writes `.scratch/<feature>/issues/NN-slug.md` on the
  local tracker, or one issue per ticket with native blocking edges on a
  real tracker.
- **implement-spec** tells exploration subagents to save notes "in a
  directory outside the repo". It creates an integration branch, per-ticket
  worktrees, calls `tdd`, then `code-review`, then closes tickets "the way
  the issue tracker closes work".
- **research** says "save it where the repo already keeps such notes",
  which is how this file got its path.
- **setup-matt-pocock-skills** writes `docs/agents/issue-tracker.md`,
  `docs/agents/domain.md`, and `docs/agents/triage-labels.md` (only if
  `triage` is installed). It also adds an `## Agent skills` block that
  points at them to `CLAUDE.md`, or to `AGENTS.md` if there is no
  `CLAUDE.md`. On GitHub/GitLab it creates labels
  (`mp:skills/engineering/setup-matt-pocock-skills/SKILL.md`). The seed
  `domain.md` holds generic consumer rules ("read GLOSSARY, check ADRs,
  proceed silently if missing") that are the same in every repo.
- **Local tracker** layout: `.scratch/<feature>/spec.md`,
  `.scratch/<feature>/issues/NN-slug.md`, with `Status:`/`Blocked by:` lines
  (`issue-tracker-local.md`). This is close to Spec Kit's `specs/NNN-x/`.

How config is discovered: skills never open `docs/agents/*.md` by path.
Hard-dependency skills say "The issue tracker and triage label vocabulary
should have been provided to you. If not, tell the user to run
`/setup-matt-pocock-skills`" (`to-spec`, `to-tickets`, `implement-spec`,
`triage`, `wayfinder`, `code-review`). Soft-dependency skills (`tdd`,
`diagnosing-bugs`, `pr`) name `GLOSSARY.md` and ADRs inline. In this repo the
config arrives through the `CLAUDE.md` "Agent skills" block, which points at
`docs/agents/issue-tracker.md` (beads). Upstream itself rejects tracker
backends beyond GitHub/GitLab/local and says custom workflows "belong in
your own `CLAUDE.md` / `AGENTS.md`, or in a fork" (`mp:SCOPE.md`,
`mp:.out-of-scope/mainstream-issue-trackers-only.md`).

## 2. Spec Kit v1.0.6: what it reads and writes

Installed per project by `specify init --ai claude` (the CLI comes from
`workstation/home.nix`, package `spec-kit`; no global skills). In this repo:

| Path                                       | Role                       | Tracked |
| ------------------------------------------ | -------------------------- | ------- |
| `.claude/skills/speckit-*/SKILL.md`        | 10 rendered commands       | yes     |
| `.specify/scripts/bash/*.sh`               | feature/path resolution    | yes     |
| `.specify/templates/*-template.md`         | spec/plan/tasks/checklist  | yes     |
| `.specify/memory/constitution.md`          | project principles         | yes     |
| `.specify/integrations/*.manifest.json`    | file hashes for upgrades   | yes     |
| `.specify/{init-options,integration}.json` | numbering, integration     | yes     |
| `.specify/workflows/speckit/workflow.yml`  | specify-plan-tasks-impl    | yes     |
| `.specify/feature.json`                    | pointer to current feature | ignored |
| `specs/NNN-slug/`                          | per-feature artifacts      | yes     |

Per-feature artifacts and who writes them (rendered skills in
`.claude/skills/speckit-*/SKILL.md`; sources `sk:templates/commands/*.md`):

| Command       | Writes                                                             |
| ------------- | ------------------------------------------------------------------ |
| specify       | `spec.md`, `checklists/requirements.md`, `feature.json`            |
| clarify       | `spec.md` (Clarifications section, max 5 questions)                |
| plan          | `plan`, `research`, `data-model`, `quickstart` (.md), `contracts/` |
| tasks         | `tasks.md` (T001 IDs, `[P]` parallel, phases by story)             |
| implement     | code; ticks `[X]` in `tasks.md`                                    |
| converge      | appends `## Phase N: Convergence` to `tasks.md` only               |
| analyze       | nothing (read-only report)                                         |
| checklist     | `checklists/<name>.md`                                             |
| constitution  | `.specify/memory/constitution.md`                                  |
| taskstoissues | GitHub issues via GitHub MCP; refuses non-GitHub remotes           |

Mechanics worth knowing:

- **Feature directory** resolution: the `SPECIFY_FEATURE_DIRECTORY` env var,
  then `.specify/feature.json`, then a fallback
  (`.specify/scripts/bash/common.sh`, `get_feature_paths`). Numbering is
  `sequential` (`NNN`) or `timestamp`, set by `feature_numbering` in
  `init-options.json` (`speckit-specify` step 3).
- **Branches**: "The spec directory name and the git branch name are
  independent" (`speckit-specify`). Branch creation is the `git`
  extension's `before_specify` hook, which is opt-in since v0.10.0
  (`sk:extensions/git/extension.yml`, `sk:CHANGELOG.md` "#2873").
- **CLAUDE.md edits**: "Spec Kit itself never touches your agent context
  file". The `agent-context` extension, opt-in, manages a block between
  `<!-- SPECKIT START -->` and `<!-- SPECKIT END -->`
  (`sk:extensions/agent-context/README.md`). This repo has not installed it.
- **Constitution** is read by specify, clarify, plan, tasks, implement,
  converge and analyze. Plan fills a "Constitution Check" gate.
- **Hooks**: every command first reads `.specify/extensions.yml`
  `hooks.before_<cmd>` / `after_<cmd>`, and runs mandatory hooks as
  `/speckit-<ext>-<cmd>` (rendered `speckit-specify` "Pre-Execution
  Checks").
- **Extensions** (`sk:extensions/`, `sk:docs/reference/extensions.md`) add
  commands and hooks. **Presets** (`sk:presets/README.md`) override
  templates and whole commands with `replace`, `prepend`, `append` or `wrap`,
  resolved through `.specify/templates/overrides/` > presets > extensions >
  core. Both install **into the project** (`.specify/extensions/<id>/`,
  `.specify/presets/<id>/`, plus rendered skills). Only catalog lists can
  live at user level (`~/.specify/extension-catalogs.yml`).
- The community catalog already has a `grill` extension ("Exhaustively
  clarify specifications and optionally sync canonical domain knowledge",
  yoshi1220/speckit-grill-me) and an ADR one, `adrkit`
  (`sk:extensions/catalog.community.json`). I did not review their code.

## 3. Overlap and conflict map

| mattpocock              | Spec Kit                        | Relation                   |
| ----------------------- | ------------------------------- | -------------------------- |
| to-spec spec (issue)    | `spec.md`                       | duplicate, different shape |
| grilling                | speckit-clarify                 | duplicate; 5-question cap  |
| GLOSSARY.md             | spec "Key Entities", data-model | partial overlap            |
| ADRs (`docs/adr/`)      | `research.md` Decision entries  | overlap, different scope   |
| ADRs                    | `constitution.md`               | complementary              |
| to-tickets (tracker)    | `tasks.md`                      | duplicate task graph       |
| implement-spec          | speckit-implement               | duplicate executor         |
| code-review spec axis   | speckit-analyze / converge      | complementary              |
| `.scratch/<f>/spec.md`  | `specs/NNN-f/spec.md`           | parallel layouts           |
| docs/agents + CLAUDE.md | agent-context block (opt-in)    | both edit CLAUDE.md        |

Notes on the rows:

- **Spec shape.** The mattpocock spec is user stories plus implementation
  and testing decisions, with no file paths. Spec Kit's `spec.md` keeps
  user stories (P1..P3), FR-NNN requirements, success criteria and key
  entities technology-agnostic, and pushes "how" into `plan.md`
  (`.specify/templates/spec-template.md`, `plan-template.md`). A
  mattpocock spec maps to `spec.md` plus the decision part of `plan.md`.
- **Clarify.** `speckit-clarify` caps at "Maximum of 5 total questions" and
  writes answers into the spec. Upstream mattpocock explicitly rejected
  question limits (`mp:.out-of-scope/question-limits.md`). Grilling
  answers live only in the conversation unless domain-modeling captures a
  term or ADR. So after `/grill-with-docs`, `speckit-analyze` cannot see
  what was decided.
- **Decisions.** `research.md` holds per-feature Decision/Rationale/
  Alternatives entries (`speckit-plan` Phase 0). ADRs are cross-feature and
  long-lived. This repo shows the drift: ADR `0004-agent-sandbox-policy.md`
  and `specs/004-agent-sandbox-policy/research.md` both record sandbox
  decisions. Nothing links them.
- **Task graph.** `implement-spec` needs tickets with blocking edges in a
  tracker. In a Spec Kit repo the graph is in `tasks.md` (phases plus `[P]`
  markers), and `speckit-taskstoissues` only targets GitHub. Beads, this
  repo's tracker, is in neither path.
- **Auto-invocation.** All rendered `speckit-*` skills ship
  `disable-model-invocation: false`, so both toolkits compete for the
  model's attention on phrases like "clarify" or "implement". `skills.nix`
  only controls the mattpocock side.

No file paths collide today. `.scratch/` is not used here, and mattpocock
never writes `specs/`. `code-review` already looks for a spec "under
`docs/`, `specs/`, or `.scratch/`" (`mp:skills/engineering/code-review/SKILL.md`).

## 4. Classifying the mattpocock artifacts

| Artifact                       | Class             | Keep in repo?                   |
| ------------------------------ | ----------------- | ------------------------------- |
| `GLOSSARY.md` / GLOSSARY-MAP   | project doc       | yes, useful to humans too       |
| `docs/adr/NNNN-*.md`           | project doc       | yes                             |
| `docs/<topic>-research.md`     | project doc       | yes, or specs/<f>/research.md   |
| `docs/agents/domain.md`        | skill scaffolding | no: generic, same in every repo |
| `docs/agents/issue-tracker.md` | skill scaffolding | no, unless the team shares it   |
| `docs/agents/triage-labels.md` | skill scaffolding | no (defaults are canonical)     |
| `## Agent skills` in CLAUDE.md | skill scaffolding | no                              |
| `.scratch/<feature>/...`       | tracker data      | no if you use beads/GitHub      |
| `.out-of-scope/*.md`           | triage knowledge  | only for public projects        |

Where the scaffolding can live instead, per the Claude Code docs:

- **`~/.claude/rules/*.md`**: user-level rules "apply to every project on
  your machine" and load before project rules [cc-mem, "User-level
  rules"]. Home Manager has `programs.claude-code.rules` (attribute name =
  file name) and `rulesDir`. This is the natural home for the generic
  `domain.md` text, the tracker-detection rule and the speckit-mode rule.
- **`CLAUDE.local.md`**: "private per-project preferences", to be
  gitignored. It is per worktree. For cross-worktree use, the docs suggest
  importing `@~/.claude/<file>.md` from it [cc-mem, "Import additional
  files"]. Caveat: having a `CLAUDE.local.md` stops Claude from reading a
  lone `AGENTS.md` by default [cc-mem, AGENTS.md table].
- **`.git/info/exclude`** (git's per-clone ignore list) keeps
  `CLAUDE.local.md` or `.scratch/` out without touching `.gitignore`.
- **Inside the skill**: what a tracker detector needs is decidable from
  the repo. A `.beads/` directory means `bd`, a GitHub remote means `gh`.
  Skills can inject that at load time with `` !`cmd` `` [cc-skills,
  "Dynamic context injection"], for example `` !`test -d .beads && echo
  beads || git remote get-url origin || true` ``.
- **Beads** already holds issues, so the tracker doc shrinks to "use bd".
  The `bd prime` output is session context anyway.
- **Skill precedence**: "personal over project". A
  `~/.claude/skills/speckit-clarify` would shadow a project's vendored one
  [cc-skills, "Skill locations and precedence"]. That is a lever for
  overriding Spec Kit without touching repos, but it hides upstream fixes
  silently. Use it sparingly.

## 5. Design options

Licensing: both repos are MIT (`mp:LICENSE` "Copyright (c) 2026 Matt
Pocock"; `sk:LICENSE` "Copyright GitHub, Inc."). Forks must keep the
notice. A `LICENSE` file next to forked skills is enough.

**(a) Thin overrides in `skills.nix`.** The file already has
`patchSkill` (frontmatter injection), `renameSkillRefs` (sed over
`SKILL.md`), `mattpocockRenames` and `extraSkillPaths`. These handle
renames and invocation flags well. Body rewrites through sed are brittle
across upstream bumps. You cannot shadow a skill by putting a same-named dir in
`./skills`: `mergedSkills` is a `symlinkJoin`, the mattpocock entries are
symlinks to directories, and nixpkgs warns that symlinkJoin "may not work
right when the passed paths contain symlinks to directories"
(`pkgs/build-support/trivial-builders/default.nix`). To replace one, add an
exclusion list to the `mattpocockAll` enumeration and ship the fork in
`./skills`.

**(b) Full forks.** Copy the `SKILL.md` and its supporting files into
`workstation/agents/skills/<name>/`. The cost is merging upstream changes
by hand. Upstream churns (`mp:CHANGELOG.md` is 65 KB) and closes feature
requests for personal workflows (`mp:SCOPE.md`), so per-person forks are
the intended route. Keep forks small: most of each skill's value is in
callees (`grilling`, `domain-modeling`, `tdd`, `codebase-design`) that can
stay upstream.

**(c) Speckit-aware mode.** Each forked skill checks for `.specify/` at the
start and switches its output target:

| Skill (fork)    | Plain repo                 | Repo with `.specify/`                  |
| --------------- | -------------------------- | -------------------------------------- |
| to-spec         | tracker issue (bd/gh)      | call `speckit-specify` with synthesis  |
| grill-with-docs | GLOSSARY, ADRs             | + answers into spec.md Clarifications  |
| to-tickets      | tracker issues + edges     | defer to `speckit-tasks`; mirror to bd |
| implement-spec  | tickets from tracker       | frontier = open tasks in tasks.md      |
| research        | `docs/<topic>-research.md` | feature topic: `specs/<f>/research.md` |

Delegating to the `speckit-*` skills through the Skill tool, instead of
re-implementing their templates, keeps presets, hooks and numbering
working. The rendered skills are model-invocable, so the call works.

**Spec Kit's own plug points instead?** An extension could hook
`after_clarify` or `before_plan` to run grilling or write ADRs, and a preset
could `wrap` `speckit.clarify`. Both install into each project's `.specify/`
and `.claude/skills/`, which adds repo files. That is the opposite of goal 1.
It is the right choice only for a repo that is shared with others who also
use Spec Kit.

## 6. Recommendation

Proposed skill set. Upstream names are kept where behaviour is unchanged.
"Fork" means a copy in `workstation/agents/skills/` with the upstream name
excluded in `skills.nix`.

| Skill                         | Source   | Change                               |
| ----------------------------- | -------- | ------------------------------------ |
| grilling, domain-modeling     | upstream | none                                 |
| codebase-design, tdd          | upstream | none                                 |
| diagnosing-bugs, research     | upstream | none (speckit rule covers research)  |
| improve-codebase-architecture | upstream | none; also read constitution (rule)  |
| grill-with-docs               | fork     | spec.md Clarifications in speckit    |
| to-spec                       | fork     | speckit: delegate to speckit-specify |
| to-tickets                    | fork     | speckit: tasks.md; plain: bd edges   |
| implement-spec                | fork     | tasks.md or bd as task graph         |
| setup-matt-pocock-skills      | drop     | replaced by the user rule            |

Minimal-change path, in order:

1. **One user rule, no forks yet.** Add
   `programs.claude-code.rules."sdd"` with about 30 lines. Cover tracker
   detection (`.beads/` means `bd`, otherwise the `gh` remote), the generic
   domain rules from `docs/agents/domain.md`, and a speckit clause: "if
   `.specify/` exists, the active feature is `.specify/feature.json`.
   Treat `constitution.md` like ADRs. The spec is `spec.md` and the task
   graph is `tasks.md`." This satisfies the "should have been provided to
   you" lines in every repo without `docs/agents/`. Try it on one fresh repo.
2. **Stop scaffolding.** Do not run `setup-matt-pocock-skills` in new
   repos. In this repo the `docs/agents/*` files and the `CLAUDE.md` block
   could go once the rule covers them. That is a separate change.
3. **Fork `to-spec` and `to-tickets`/`implement-spec`** only after step 1
   shows where the rule is not enough. The tracker-to-tasks.md switch is
   the likely gap.
4. **ADR numbering.** In the forked `grill-with-docs`, or in the rule,
   require a check of all branches (`git ls-tree` on each local branch)
   before picking `NNNN`. Or switch to date prefixes.

Open decisions for you:

- In a Spec Kit repo, is the `spec.md` from `speckit-specify` the only spec?
  Or do you still want a tracker issue that points to it (a bd epic linking
  `specs/NNN/`)?
- Should grilling feed `speckit-clarify`, so its answers land in the spec,
  or replace it? Replacing it needs a user-level `speckit-clarify` shadow
  (section 4), which affects every Spec Kit repo.
- How do ADRs and `research.md` relate? One option: promote a
  `research.md` decision to an ADR only when it meets the three-part ADR
  bar. Who links them?
- Should the `agent-context` and `git` Spec Kit extensions stay off? Both
  are off today, which fits "few repo writes".
- Name forks after upstream (shadow) or prefix them (e.g. `sdd-to-spec`)?
  Prefixes avoid confusion with upstream docs but break callers that name
  the upstream skill.

## Unverified

- Whether `symlinkJoin` actually mis-merges a same-named dir in `./skills`
  with a mattpocock entry. I relied on the nixpkgs warning and did not test a
  build.
- The community `grill` and `adrkit` Spec Kit extensions: listed in the
  catalog. I did not read their code.
- Whether a skill-to-skill Skill call into `speckit-specify` passes
  arguments as `$ARGUMENTS`. The docs describe `$ARGUMENTS` for user
  invocation [cc-skills], not for model calls.

## Sources

- [mp] <https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d>
- [sk] <https://github.com/github/spec-kit/tree/v1.0.6> (`96c9bd6`)
- [cc-mem] <https://code.claude.com/docs/en/memory>
- [cc-skills] <https://code.claude.com/docs/en/skills>
- Home Manager options `programs.claude-code.rules` and `rulesDir`
  (looked up through mcp-nixos)
- This repo: `workstation/agents/skills.nix`, `workstation/home.nix`,
  `.specify/`, `.claude/skills/speckit-*`, `docs/agents/`, `docs/adr/`
