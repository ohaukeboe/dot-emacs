# Implementation Plan: Agent Context Hygiene

**Branch**: `007-context-hygiene` | **Date**: 2026-10-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-context-hygiene/spec.md`

## Summary

This feature closes the context-engineering gaps in the Claude Code setup
that the research report found. Every change is home-manager configuration
under `workstation/agents/`, plus two instruction files.

- **Context size**: a new `statusline.nix` owns the status line and styles
  the size at 200K and 400K.
- **Compaction**: `autoCompactWindow` set to 400K.
- **Reset workflow**: a new Claude-only `/bead-handoff` skill that writes
  with `bd note`.
- **Instructions**: drop cavecrew, deny the five task-list tools, and
  replace the beads block with one line.
- **Noise and size**: `RTK_SUPPRESS_HOOK_WARNING` and
  `MAX_MCP_OUTPUT_TOKENS=10000`.
- **Loadout**: `mobile-mcp` and `chrome-devtools` become default-off
  plugins; add `skillOverrides`; patch the beads commands; return the
  listing budget to 0.01.
- **Records**: an ADR and GLOSSARY entries.

Each value is a typed option guarded by an assertion. Two new fast flake
checks cover the status line and the rtk banner. Research details are in
[research.md](research.md).

## Technical Context

**Language/Version**: Nix (flakes, nixpkgs unstable), home-manager modules;
Bash via `writeShellApplication` (shellcheck at build time); Markdown skill
files.

**Primary Dependencies**:

| Dependency                          | Version or role                     |
|-------------------------------------|-------------------------------------|
| Claude Code                         | 2.1.303, via `programs.claude-code` |
| `jq`, `coreutils`                   | from nixpkgs                        |
| rtk                                 | 1.0.1                               |
| beads (`bd`) and its plugin         | plugin marketplace 1.3.1            |
| caveman input                       | statusline script                   |
| `mobile-mcp`, `chrome-devtools-mcp` | as packaged today                   |

**Storage**: no database. State lives in three places:

- the beads notes field (the handoff note)
- the generated `~/.claude/settings.json`
- the opting-in repository's `.claude/settings.local.json`

**Testing**:

- `nix flake check`, with two new `runCommand` checks: `context-statusline`
  and `rtk-banner`.
- Evaluation-time assertions.
- `nix build` of every host.
- The manual post-deploy checks in [quickstart.md](quickstart.md).

**Target Platform**: NixOS hosts in `machines/machines.nix`: work-laptop,
desktop, laptop and dig-laptop.

**Project Type**: declarative system and user configuration (Nix flake).

**Performance Goals**:

- The status line renders in well under 100 ms per update, with one jq call
  and one bash call.
- Handoff round trip under 2 minutes (SC-002).

**Constraints**:

- Everything evaluates purely.
- No ambient state.
- The sandbox is not widened.
- The user's settings file stays read-only (declarative).

**Scale/Scope**: 4 hosts and about 12 files touched. No new flake inputs.

No NEEDS CLARIFICATION remain: [research.md](research.md) resolves all of
them.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

All gates pass.

- **I. Evaluation-time checks (pass)**:
  - Every value is typed: `ints.positive`, `ints.between`, `enum`,
    `attrsOf enum`.
  - Ordering assertions guard the thresholds.
  - New shell is built with `writeShellApplication`.
  - Executables are referenced through `lib.getExe`.
- **II. Determinism (pass)**:
  - No new inputs.
  - The plugins are built in Nix.
  - The same configuration applies on all 4 hosts.
  - The punkt keys are derived from the input, not listed by hand.
- **III. Fast gate (pass)**: both new checks are small `runCommand`s, with
  no VM or large closure.
- **IV. Single source of truth (pass)**:
  - `bd prime` is the only source of the beads rules.
  - There is one memory store.
  - CLAUDE.md and AGENTS.md change together.
  - An ADR records the decisions.
- **V. Toggleable modules (pass)**:
  - The toggles are `statusLine.enable` and the `optIn.servers` list.
  - `statusline.nix` follows the `agents.*` pattern, with no fork per
    machine.
- **Formatting and commits (pass)**: `nix fmt` before commit; Conventional
  Commits.
- **Docs parity (pass)**: the CLAUDE.md and AGENTS.md beads blocks are
  replaced identically.

**Post-design re-check**: still passes. There is one known deviation, and it
is not a violation. The FR-019 opt-in is a file in the opting-in repository,
outside this flake. That is per-project data, not machine state, so
Principle II does not govern it.

## Project Structure

### Documentation (this feature)

```text
specs/007-context-hygiene/
├── plan.md              # this file
├── research.md          # Phase 0: decisions R1–R7, refuted/unverifiable claims
├── data-model.md        # Phase 1: typed options, settings keys, runtime entities
├── quickstart.md        # Phase 1: build-time and post-deploy validation
├── contracts/
│   ├── statusline.md        # stdin/stdout contract + test vectors
│   ├── bead-handoff.md      # skill frontmatter, steps, postconditions
│   ├── deployed-settings.md # expected settings.json keys
│   └── mcp-opt-in.md        # default-off plugins and the opt-in entry
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks), not created here
```

### Source Code (repository root)

```text
workstation/agents/
├── statusline.nix          # NEW  agents.context.* options, statusLine, assertions
├── default.nix             # import statusline.nix; autoMemoryEnabled; drop budget 0.02
├── caveman.nix             # remove statusLine block (keep hooksDir)
├── rtk.nix                 # env.RTK_SUPPRESS_HOOK_WARNING; rtk-banner check
├── beads.nix               # permissions.deny task tools; patched beads commands
├── mcp-servers.nix         # agents.mcp.optIn.*; hm-mobile/hm-browser plugins;
│                           #   MAX_MCP_OUTPUT_TOKENS; opencode keeps both servers
├── skills.nix              # agents.skillOverrides; listing field; drop cavecrew;
│                           #   fold plugins + claude-only skills into skillsWithPlugin
├── skills-claude-only/
│   └── bead-handoff/SKILL.md   # NEW
├── subagents-docs.md       # drop cavecrew + code-review-graph mentions
└── skills/user-testing/references/drivers/{mobile,chrome-devtools}.md  # tool prefixes
machines/dig-laptop/default.nix  # punkt-* skillOverrides from readDir
tests/context-statusline.nix     # NEW flake check
flake.nix                        # register new checks
CLAUDE.md, AGENTS.md             # beads block -> one-line pointer
.claude/skills/add-mcp-server/SKILL.md  # document opt-in servers
docs/adr/0008-agent-context-hygiene.md  # NEW: single memory store, reset
                                        #   workflow, opt-in loadout, kept duplicates
GLOSSARY.md                      # Agents / context: context size, warning point,
                                 #   summarization point, handoff note, tool-server loadout
```

**Structure Decision**: follow the existing pattern of one concern per file
under `workstation/agents/`, each with its own `agents.*` options and
assertions. Examples are `process-cap.nix` and `commit-gate.nix`.

`./skills` feeds opencode and `~/.agents/skills` as well as Claude Code. The
handoff skill must stay out of those, so it goes in a new
`skills-claude-only/` directory, joined into `skillsWithPlugin` only.

## Delivery order (for /speckit-tasks)

The stories are independent. Suggested order: highest value first, and
smallest blast radius first within a priority.

1. **US1 status line** (P1). New module plus check; no other module depends
   on it.
2. **US2 handoff skill** (P1). One new skill file plus `skills.nix` wiring.
3. **US5 rtk banner** (P2). One env var plus check.
4. **US3 compaction** (P2). One option plus an assertion that depends on
   `agents.context`, so after US1.
5. **US4 instructions** (P2). Deny rules; edits to CLAUDE.md, AGENTS.md and
   subagents-docs; cavecrew removal.
6. **US7 MCP output limit** (P3). One env var.
7. **US6 loadout** (P3). The largest change: plugins, `skillOverrides`,
   beads patch, budget. Do it last, and check `/doctor` before and after.
8. ADR, GLOSSARY and follow-up beads: rtk activation dead code,
   `prime.max-memory-chars`, and opencode loadout parity.

## Risks

- **A default-off skills-dir plugin behaves differently from the docs.**
  Mitigation: the quickstart US6 check; the fallback is the global server.
- **The patched beads plugin is not re-cached, because its version stays
  1.3.1.** Mitigation: add a version suffix in the patch.
- **The task-tool deny breaks the agent-teams task list.** Accepted in the
  spec Assumptions.
- **`bd init` re-adds the beads block to CLAUDE.md.** The ADR notes it; the
  command is rarely re-run.
- **The status-line colours are unreadable in the Emacs terminal.** The
  thresholds and styles are options; tune them after quickstart check Q1.

## Complexity Tracking

No constitution violations need justifying.
