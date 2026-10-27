# Context engineering in Claude Code: mapping Breunig's 2026 talk to this setup

Research report. Question: which techniques and failure modes in Drew
Breunig's [The State of Context Engineering][article] (2026-10-24) can this
setup apply through Claude Code, and how? This repo manages that Claude Code
config with Nix.

Checked on 2026-10-27 against:

- the article and the papers and posts it cites
- the Claude Code docs at `code.claude.com/docs` and the API docs at
  `platform.claude.com/docs`
- this repo at `ff64882`, plus the generated `~/.claude/CLAUDE.md`

I did not read `sops/`, `private/` or any credential files.

## TL;DR

The talk names six tactics: augmentation, tool loadout, quarantine, pruning,
summarization and offloading. It names four classic failure modes (poisoning,
distraction, confusion, clash) and two new ones (fighting the weights,
context inertia). It also predicts a third new one, "memory rot". Its main
practical advice is to **reset the context** when it gets large: Breunig's
own warning point is about 200K tokens. Throw the conversation away and keep
the work in the environment. Four research teams converged on that fix.
Compaction alone does not undo inertia.

Claude Code has a native mechanism for all six tactics. This repo already
does well on augmentation, offloading (beads, codebase-memory), at-source
pruning (rtk, caveman-shrink), skill loadout (build-time filtering plus a
listing budget) and deterministic enforcement (hooks, deny rules, sandbox).

The gaps:

- No context-size signal. The statusline shows only the caveman badge.
- The auto-compact window is left at its default, which sits near the top of
  the 1M window.
- No reset/handoff workflow.
- The `cavecrew-*` subagents the global CLAUDE.md recommends are not
  installed.
- All nine MCP servers load in every project.
- Auto memory is still on beside `bd remember`.
- rtk prints a warning into every Bash result.

## Summary table

| Technique            | Claude Code mechanism                        | Status here   |
|----------------------|----------------------------------------------|---------------|
| Poisoning            | `/rewind`, checkpoints, `/clear`             | Manual        |
| Distraction          | `autoCompactWindow`, `/clear`, statusline    | Gap: defaults |
| Confusion            | `skillOverrides`, MCP disable, `paths:`      | Partial       |
| Clash                | one memory store, `/doctor prompt-audit`     | Partial       |
| Fighting the weights | hooks and deny rules, not CAPS prose         | Mostly done   |
| Context inertia      | handoff note + `/clear`, SessionStart hook   | Partial (bd)  |
| Memory rot           | prune `bd` memories, auto memory off         | Gap           |
| Augmentation         | skills, CLAUDE.md, MCP (context7, LSP)       | Done          |
| Tool loadout         | tool search, `skillOverrides`, MCP disable   | Partial       |
| Quarantine           | subagents, forks, worktrees, teams           | Partial       |
| Pruning              | rtk, caveman-shrink, PostToolUse output      | Partial       |
| Summarization        | auto-compact, `/compact <focus>`, PreCompact | Defaults only |
| Offloading           | beads, files, codebase-memory, plan file     | Done          |
| Deterministic vs LLM | hooks, deny rules, sandbox, gates            | Done          |

## Failure modes

### Context poisoning

**Source.** The article defines it as an error or hallucination that enters
the context and keeps being referenced. Its example is Gemini 2.5 hunting
for FireRed's iced tea while playing Pokémon Red. The definition comes from
Breunig's [How Contexts Fail][fail]. Gemini's
[2.5 technical report][gemini] says such goals can take "a very long time to
undo".

**Claude Code mechanisms.**

- `/rewind` (or Esc Esc) restores the conversation, the code or both to a
  checkpoint. It can also "Summarize from here" or "Summarize up to here",
  which cuts a poisoned stretch out of the history.
  ([checkpointing][cc-checkpoint])
- Bash-made file changes and subagent edits are not reliably restored.
  ([checkpointing][cc-checkpoint])
- The best-practices page says: after two failed corrections, run `/clear`
  and write a better prompt rather than a third correction.
  ([best practices][cc-best])

**This repo.** Nothing beyond the defaults, which is fine, since this is a
habit rather than config. Writes to the working tree are reversible through
git, and the commit gate keeps them reviewable
(`docs/adr/0006-agent-commit-gate.md`).

### Context distraction

**Source.**

- Gemini 2.5's Pokémon agent began "repeating actions from its vast history"
  once its context passed about 100K tokens. ([Gemini report][gemini])
- Camassa and Shiller, [Do as I Say, Not as I Do][camassa]: conversations
  with N prior assistant turns that contradict an instruction.
  - Opus 4.6 fell to 50% or lower instruction-following at N=16 on
    fixed-output tasks and N=31 on task-based ones.
  - Sonnet 4.6 fell at N=8 and N=22.
  - Reasoning helps but does not remove the effect.
  - Telling the model that the earlier turns were hardcoded "mitigates but
    does not resolve" the conflict.
- Breunig resets at about 200–300K tokens. He applies this to coding: a long
  back-and-forth over CSS seeds "bad examples".

**Claude Code mechanisms.**

- `autoCompactWindow` sets when auto-compaction runs, from 100K to 1M
  tokens. ([model config][cc-model])
  - It can be set per model with `/autocompact 300k`, or for every model in
    settings.
  - `CLAUDE_CODE_AUTO_COMPACT_WINDOW` overrides both.
  - With no window set, Claude Code compacts at the model's context limit.
    The best-practices page describes the default as "compaction near the
    top" of a 1M window. ([best practices][cc-best])
  - **Unverified:** the exact default threshold for Opus 5.5. That table was
    cut off in my fetch.
- The statusline gets `context_window.used_percentage` and
  `context_window.total_input_tokens` on stdin, so it can show a size
  warning. ([statusline][cc-statusline])
- `/context` gives a live breakdown, and `/clear` starts fresh.
  ([context window][cc-ctx])

**This repo.**

- No auto-compact window is set. No `autoCompactWindow` or
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` appears in
  `workstation/agents/default.nix:345-349`.
- The statusline is only the caveman badge
  (`workstation/agents/caveman.nix:76-79`), so you get no warning at Breunig's
  200K point.

### Context confusion

**Source.**

- Irrelevant content, typically unneeded tool definitions, degrades output.
  ([How Contexts Fail][fail])
- A quantized Llama 3.1 8B fails with 46 tools and succeeds with 19.
  ([arXiv 2411.15399][lessismore])
- Above about 30 tools, descriptions overlap; above 100, failure is "virtually
  guaranteed". ([RAG-MCP][ragmcp])
- Breunig turns ChatGPT/Claude memory off because it mixes unrelated contexts.
  ([article][article])

**Claude Code mechanisms.** See Tool loadout below. Also:

- Path-scoped `.claude/rules/*.md` (`paths:` frontmatter) load only when a
  matching file is touched. ([memory][cc-memory])
- Auto memory is on by default. Turn it off with `autoMemoryEnabled: false`.
  ([memory][cc-memory])

**This repo.**

- `autoMemoryEnabled` is unset, so auto memory is on. The repo's own rule is
  "use `bd remember` ... do NOT use MEMORY.md files" (`CLAUDE.md:23`). That
  makes two memory systems that can diverge.
  `~/.claude/projects/-home-oskar-projects-dot-emacs/memory/` exists but is
  empty today.
- There are no `.claude/rules/`. The project `AGENTS.md` is 434 lines. CLAUDE.md
  points to it (`CLAUDE.md:68`) rather than loading it. The docs say to keep
  each CLAUDE.md under 200 lines. ([memory][cc-memory])

### Context clash

**Source.** Information gathered across turns or sources conflicts.
Splitting a prompt across turns cut scores by 39% on average, and o3 fell
from 98.1 to 64.1. "When LLMs take a wrong turn ... they get lost and do not
recover." ([arXiv 2505.06120][lost]) The talk widens this to tools and
skills that conflict inside the harness. ([article][article])

**Claude Code mechanisms.**

- `/doctor prompt-audit` audits CLAUDE.md and rules for conflicts (v2.1.283+,
  per [memory][cc-memory]). I have not run it here.
- `claudeMdExcludes` skips ancestor CLAUDE.md files. ([memory][cc-memory])

**This repo.** Beads guidance reaches the model three times:

- the managed block in `CLAUDE.md` (lines 5–59)
- the same block in `AGENTS.md:345-390`, if loaded
- `bd prime` output from the beads plugin's SessionStart/PreCompact hooks
  (`workstation/agents/beads.nix:10-15`)

**Not verified:** how large `bd prime` output is, or whether it overlaps the
CLAUDE.md block.

Two more overlaps:

- `CLAUDE.md:21` forbids the harness's own TodoWrite/TaskCreate tools, which
  also fights the weights (next section).
- The global CLAUDE.md tells the agent to use `cavecrew-*` agents
  (`workstation/agents/subagents-docs.md:41-50`), but none is installed
  (see Quarantine). The instruction clashes with the tools actually there.

### Fighting the weights

**Source.** The model resists because training pushes another way. Signs
include repeated instructions, ALL CAPS and pleading. The talk's example is
Claude Code's own system prompt, which repeats "make parallel tool calls" up
to seven times. ([Don't fight the weights][weights], [article][article])

**Claude Code mechanisms.** The docs say the same thing in harness terms: "If
you keep adding emphasis to a CLAUDE.md line and Claude still misses it,
that's a sign the line belongs in a hook." ([best practices][cc-best])
Hooks, deny rules, the sandbox and managed settings are the deterministic
side.

**This repo.** It already moves its hard rules into the harness:

- **Commit rule.** CLAUDE.md states it, and the PreToolUse rewriter chain
  plus `commit-gate.py` enforce it (`workstation/agents/default.nix:91-106`).
  ask rules back it up (`default.nix:355-361`) ("Give the CLAUDE.md git rule
  teeth", `default.nix:350`).
- **Formatting.** A PostToolUse hook runs it
  (`workstation/agents/format-on-edit.nix:76-88`).
- **Memory and runtime.** Caps enforce them (`process-cap.nix`,
  `memory-cap.nix`).

What is left is prose that pushes against trained behaviour:

- `CLAUDE.md:21` says "do NOT use TodoWrite, TaskCreate". If it matters,
  enforce it with a deny rule on those tools.
- The "prefer lsp-mcp / codebase-memory over text search" line
  (`workstation/agents/agents-global.md:13`) asks the model to skip
  Grep/Read, which are the tools it was trained on. **Not measured:** how
  often the model follows that line.

### Context inertia

**Source.** Inertia is when the model commits to a hypothesis, subtask or
goal and keeps pursuing it after it should stop.
([Context Inertia][inertia]) Four groups converged on "throw the context
away and keep the work":

- **Anthropic's Memento** ([self-replicating AI][memento]).
  - After a 1.5-hour timeout per iteration, the agent writes a short
    "notebook" of the strategies it tried and the failures it hit.
  - A fresh instance "inherits the codebase and environment from its
    predecessor as well as the notebook."
- **Fork-and-Flush** ([arXiv 2610.07447][fork]).
  - At 33% and 66% of the budget, it forks 4 branches that keep the
    workspace and start a fresh chat. The best branch carries on.
  - Fork-and-Flush beats single-run and best-of-4 by 66.0% and 44.4%.
  - Inertia "persists despite periodic compaction".
- **Stateless Language Agents** ([arXiv 2610.07625][sla]).
  - The harness owns the research state and rebuilds a fresh, role-specific
    context for every invocation.
  - SLA reaches the strongest kernel baseline's result with over 84% fewer
    tokens.
- **Scaling Discovery Requires Forgetting** ([arXiv 2610.20563][forget]).
  - It periodically discards every session and the candidate history, and
    keeps only the best candidate.
  - It gains up to 15% over parallel agents and up to 39% over a single
    agent.

**Claude Code mechanisms.**

- `/clear` drops the conversation and keeps the working tree.
- SessionStart hooks with matcher `clear` (or `compact`) inject
  `additionalContext` into the new session. ([hooks][cc-hooks])
- Durable state can live in files, git or beads.
- Forks (`/subtask`) or worktree-isolated subagents (`isolation: worktree`)
  can explore alternatives from the current state, which approximates
  fork-and-flush by hand. ([subagents][cc-sub])
- `/loop` or scheduled runs could drive a timed Memento-style reset.
  **Unverified** that a loop iteration can `/clear` itself.

**This repo.** Half of a reset loop exists:

- Beads is the offload store, and `bd prime` re-primes on SessionStart,
  which includes `clear` and `compact`. The beads plugin README says
  SessionStart fires on `startup|resume|clear`; I did not check the hook
  file itself.
- The Emacs worktree command starts a fresh session per worktree
  (`workstation/emacs/config.org:4796-4856`).

Missing is the step before the reset: a habit or command that writes a
Memento-style note ("tried X, failed because Y, next try Z") into the bead
and then `/clear`s.

### Memory rot (prediction)

**Source.** After six months on a Hermes agent, Breunig found that
self-written skills and memories pile up conflicting fixes. "We also need to
think about strategic forgetting." ([article][article]) This is his
prediction, not a measured result.

**Claude Code mechanisms.**

- Auto memory loads only the first 200 lines or 25 KB of MEMORY.md.
  ([memory][cc-memory])
- `/doctor prompt-audit` audits CLAUDE.md and rules.
- `/skill-doctor` finds unused skills. ([skills][cc-skills])

**This repo.** Skills are pinned through Nix inputs and patched at build
time (`workstation/agents/skills.nix:11-21`), so the agent cannot quietly
rewrite them. That rules out the main drift path Breunig describes.

`bd remember` memories do accumulate, and nothing reviews them. A periodic
`bd memories` review, or expiry, would be the strategic-forgetting step.
**Not checked:** whether beads supports memory expiry.

## Tactics

### Context augmentation (RAG, skills)

**Source.** [How to Fix Your Context][fix]: "if you treat your context like a
junk drawer, the junk will influence your response".

**Claude Code mechanisms.**

- Skills use progressive disclosure: only the name and description stay in
  context, and the body loads when the skill is invoked. ([skills][cc-skills])
- CLAUDE.md, `@imports`, path-scoped rules. ([memory][cc-memory])
- MCP servers.

**This repo.** Augmentation is well covered:

- context7, kagi, mcp-nixos, lsp-mcp and codebase-memory
  (`workstation/agents/mcp-servers.nix:66-115`)
- the Emacs MCP tools (`config.org:4672-4694`, `4862-4882`)
- a curated skill set (`workstation/agents/skills.nix`)

### Tool loadout

**Source.** The talk's enterprise anecdote is 600 skills loaded at startup.
The papers are [RAG-MCP][ragmcp] (keeping under 30 tools gave up to 3x the
selection accuracy) and [Less is More][lessismore] (+44% for Llama 3.1 8B on
BFCL).

**Claude Code mechanisms.**

- **MCP tool search.** `ENABLE_TOOL_SEARCH` defaults to `auto`, which defers
  MCP tool definitions once they exceed 10% of context. `auto:N` changes the
  threshold, and `alwaysLoad` pins a server or tool. ([MCP][cc-mcp])
  - This session shows it is active here: about 200 MCP tools appear only as
    deferred names.
- **Per-project MCP enable/disable.** `disabledMcpServers`,
  `enabledMcpServers`, or the `/mcp` toggle. The best-practices page notes
  that connected servers add tool names and instructions "even when you're
  not using them". ([MCP][cc-mcp], [best practices][cc-best])
- **Skill listing controls.**
  - The listing budget defaults to 1% of the context window
    (`skillListingBudgetFraction`).
  - When the listing is over budget, the least-invoked skills' descriptions
    are dropped first.
  - `skillOverrides` sets a skill to `on`, `name-only`,
    `user-invocable-only` or `off`. It does not apply to plugin skills.
  - `disable-model-invocation`, and `paths:` frontmatter that loads a skill
    only for matching files.
  - `/doctor` and `/skill-doctor` estimate the cost and find unused skills.
  ([skills][cc-skills])

**This repo.**

- **Done.**
  - Build-time skill filtering through `patchSkill`
    (`workstation/agents/skills.nix:11-21`).
  - mattpocock skills are not auto-invoked by default (`skills.nix:114-146`).
  - 1,101 bulk skills are commented out because they "blow the skill-listing
    budget" (`skills.nix:243-255`).
  - `skillListingBudgetFraction = 0.02` (`default.nix:349`).
- **Gap: per-project servers.**
  - Nine MCP servers are global (`mcp-servers.nix:55,66-115`), including
    mobile-mcp and chrome-devtools in every repo.
  - Tool search softens the token cost, but server instructions still load.
    This session's prompt carries instruction blocks for mobile-mcp, github,
    context7, mcp-nixos and codebase-memory.
  - Set per-project enablement, or `/mcp` disable mobile-mcp and
    chrome-devtools in repos that don't use them.
- **Gap: skill listing.**
  - Skills listed this session: 72 user skills, about 16 project skills,
    plus plugin skills. They include Punkt/Oslo-kommune design-system skills
    and `speckit-*`, which are irrelevant in this repo.
  - The `skills.nix:248` comment says `CLAUDE_SKILL_FILTER` does not exist.
    `skillOverrides` (`name-only` / `user-invocable-only`) and `paths:` are
    the documented runtime filters, and they would let the budget go back
    toward 1%.

### Context quarantine

**Source.** Anthropic's multi-agent research system "outperformed
single-agent Claude Opus 4 by 90.2%" and used "about 15× more tokens than
chats". It notes that "most coding tasks involve fewer truly parallelizable
tasks". ([multi-agent][multiagent])

**Claude Code mechanisms.**

- Subagents run in their own context window and return only a summary.
  ([subagents][cc-sub])
- Frontmatter controls:
  - `tools`, `model`, `skills`, `mcpServers`
  - `omitClaudeMd`
  - `isolation: worktree`
  - `background`
  - `autoCompactWindow`
- Forks inherit the parent's conversation.
- A skill with `context: fork` runs in a subagent.
- Agent teams.

**This repo.**

- Guidance is in `workstation/agents/subagents-docs.md:1-50`, and agent teams
  are enabled (`default.nix:348`).
- **Gap:** `cavecrew-investigator`, `-builder` and `-reviewer` are
  recommended in the global CLAUDE.md (`subagents-docs.md:41-50`), but no
  agent files are installed.
  - `~/.claude/agents` does not exist, and nothing sets
    `programs.claude-code.agents`.
  - The repo inventory found the files upstream (caveman's
    `agents/cavecrew-*.md`). **Not checked by me.**
  - This session's agent list has no `cavecrew-*` type.
  - Either install them, or drop the recommendation to remove a clash.
- Custom agents with `omitClaudeMd: true` and a narrow `mcpServers` list
  would give research subagents a much smaller starting context.

### Context pruning

**Source.** [Provence][provence] cut about 95% of an article while keeping
the relevant part. The talk notes that early compaction stages in Claude
Code and Codex "strip out tool results", and warns: "mind your prompt
caching". ([article][article])

**Claude Code mechanisms.**

- **API.** Context editing `clear_tool_uses_20250919` (trigger 100K, keep 3)
  and `clear_thinking_20251015`. Clearing invalidates the cache.
  ([context editing][api-ctxedit])
- **Claude Code client.** A client-side "clear old tool results" feature is
  **not documented** in the pages I fetched.
- **Deterministic pruning at the source.**
  - A PostToolUse hook can replace any tool's output with
    `updatedToolOutput`. ([hooks][cc-hooks])
  - `MAX_MCP_OUTPUT_TOKENS` defaults to 25,000. MCP text results over 50,000
    characters are saved to a file instead. ([MCP][cc-mcp])
- **Partial pruning.** `/rewind` → "Summarize up to here".
  ([checkpointing][cc-checkpoint])

**This repo.** Pruning happens at the source, which keeps the cached prefix
intact:

- rtk rewrites Bash commands to compact their output
  (`workstation/agents/rtk.nix:27-32`).
- caveman-shrink wraps most MCP servers as a compressing stdio proxy
  (`mcp-servers.nix:22-33`).

Gaps:

- context7 and kagi are not shrink-wrapped. This research's single
  `kagi_extract` returned the whole talk transcript.
- **Bug-like finding.** Every Bash result in this session starts with
  `[rtk] /!\ No hook installed — run rtk init -g ...`, often twice. rtk
  checks for its own hook in `settings.json`, but here it runs inside
  `agent-bash-rewriter-chain` (`default.nix:27-168`). That is pure noise in
  every tool result. **Not verified:** how to silence the check.
- `format-on-edit` adds diagnostics through `additionalContext`
  (`format-on-edit.nix:65-69`). That is useful, but **not checked:** whether
  it is capped.

### Context summarization (compaction)

**Source.** Compaction rewrites history into a briefing. The talk's
refinement is to filter for relevance before summarizing. Fork-and-Flush
shows compaction alone does not undo inertia. ([article][article],
[fork][fork])

**Claude Code mechanisms.**

- Auto-compaction and `/compact <focus>` (e.g. "keep the API changes and the
  test commands"). ([context window][cc-ctx])
- `/rewind` partial summaries.
- PreCompact (exit 2 blocks compaction) and PostCompact hooks.
  ([hooks][cc-hooks])
- What survives compaction ([context window][cc-ctx]):
  - project CLAUDE.md, unscoped rules and auto memory are re-read
  - up to five recently modified files are re-read
  - invoked skill bodies are re-injected, capped at 5K tokens each and 25K
    total
  - SessionStart `compact` hooks run again
  - path-scoped rules and nested CLAUDE.md are summarized away
- Idle sessions past about 200K tokens are compacted before the one-hour
  cache expires. ([best practices][cc-best])
- **API.** Server-side compaction exists. The overview and the
  context-editing page disagree on the parameter names, so **unverified**
  which is current. ([compaction][api-compact])

**This repo.** It runs the defaults, plus beads' PreCompact `bd prime`
(`beads.nix:10-15`). Nothing guides what the summary should keep.

Two notes:

- Rules that must survive compaction should stay in the root CLAUDE.md or
  in unscoped rules. Path-scoped rules are summarized away.
- Skills such as `caveman` should keep their key instructions at the top of
  `SKILL.md`, since truncation keeps the start. ([context window][cc-ctx])

### Context offloading

**Source.** Offloading means storing information outside the context. The
cited example is Anthropic's
[think tool][think], with up to 54% improvement. Anthropic's
[context-engineering post][acontext] describes the same pattern as
"structured note-taking".

**Claude Code mechanisms.**

- files and git
- plan-mode plans, which are re-injected after compaction
- auto memory
- the API memory tool (`memory_20250818`) ([memory tool][api-memory])
- MCP stores

**This repo.** Strong:

- **beads** for tasks and memories (`CLAUDE.md:5-59`, `beads.nix`).
- **codebase-memory** with auto-indexing (`mcp-servers.nix:80-83,124-127`).
- **research notes** in `docs/*-research.md` and ADRs in `docs/adr/`.

### Deterministic vs probabilistic

**Source.** The talk's closing thesis: "our job is to choose when to be
deterministic ... and when to be probabilistic". ([article][article]) The
Claude Code docs have a matching table: CLAUDE.md, prompts and skills on one
side; hooks, deny rules, the sandbox and managed settings on the other.
([best practices][cc-best])

**This repo.** This is the setup's strongest point:

- the sandbox (`workstation/agents/sandbox.nix`,
  `docs/adr/0004-agent-sandbox-policy.md`)
- the commit gate (`docs/adr/0006-agent-commit-gate.md`)
- the process and memory caps
- format-on-edit
- the build-time skill gating

The context-size reset is still left to the probabilistic side, which here
means the model or the user noticing.

## Suggested changes, in priority order

1. **Show context size in the statusline.**
   - Wrap the caveman statusline (`caveman.nix:76-79`) in a script that also
     prints `context_window.total_input_tokens` from stdin JSON. Colour it
     at 200K and 400K.
   - This is deterministic and cheap, and it puts Breunig's warning point in
     front of you. ([statusline][cc-statusline])
2. **Lower the auto-compact window.**
   - Set `programs.claude-code.settings.autoCompactWindow` (e.g. `400000`)
     in `default.nix` near line 349.
   - That caps worst-case distraction. Pair it with the reset habit in step
     3, since compaction alone keeps inertia. ([model config][cc-model],
     [fork][fork])
   - Trade-off: more compactions, and each one is a large request.
3. **Add a Memento-style handoff-and-reset command.**
   - Add a small user-invocable skill, `disable-model-invocation: true`, in
     `workstation/agents/skills/`.
   - It writes "tried / failed / next" to the current bead (`bd update
     --notes` or a comment; check the exact `bd` syntax), then tells the user
     to `/clear`.
   - `bd prime` on SessionStart `clear` restores the pointer.
     ([memento][memento], [hooks][cc-hooks])
4. **Fix the cavecrew clash.**
   - Install the caveman `agents/cavecrew-*.md` through
     `programs.claude-code.agents`.
   - Or remove `subagents-docs.md:41-50` and the `cavecrew-*` mention at
     `subagents-docs.md:14-15`.
5. **Silence rtk's "No hook installed" banner.** It appears in every Bash
   result. The fix is unverified: look for an rtk config option or env var,
   or have the chain filter stderr.
6. **Turn auto memory off.**
   - Set `programs.claude-code.settings.autoMemoryEnabled = false`.
   - This leaves `bd remember` as the single memory store and removes a
     clash with `CLAUDE.md:23`. ([memory][cc-memory])
7. **Scope MCP servers.**
   - Disable mobile-mcp and chrome-devtools (and github-mcp where unused) by
     default, and enable them per project with `enabledMcpServers` /
     `/mcp`.
   - Or use `ENABLE_TOOL_SEARCH=auto:5` if instruction blocks matter less.
     ([MCP][cc-mcp])
8. **Prune the skill listing at runtime.**
   - Set `skillOverrides` to `name-only` or `user-invocable-only` for
     domain-specific skills (Punkt, speckit, understand-*), or give them
     `paths:`.
   - Then try `skillListingBudgetFraction` back at 0.01. Check with
     `/doctor` and `/skill-doctor`. ([skills][cc-skills])
9. **Shrink-wrap kagi and context7**, or set a lower `MAX_MCP_OUTPUT_TOKENS`.
   ([MCP][cc-mcp])
10. **Run `/doctor prompt-audit` once** on the global, project and AGENTS.md
    files, to find beads-guidance duplication and conflicts.
    ([memory][cc-memory])
11. **Turn the TodoWrite/TaskCreate ban into a deny rule**, if it matters
    (`CLAUDE.md:21`). Otherwise drop it, which is "don't fight the weights".
    ([best practices][cc-best])

## Unverified or not found

- The default auto-compact threshold for Opus 5.5. The model-config table was
  cut off in my fetch.
- A client-side Claude Code tool-result clearing (microcompaction) feature
  is not in the docs I fetched.
- The API compaction parameter names: the compaction overview and the
  context-editing page disagree.
- The size of the `bd prime` output, and the contents of the beads plugin's
  hook file, which comes from the nvfetcher source.
- Whether beads supports memory expiry or review.
- How to suppress rtk's banner.
- That a `/loop` iteration can `/clear` itself.
- The `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env var appears in no doc I fetched.
  Don't use it.

## Sources

Article and the works it cites:

- `article`: Breunig, "The State of Context Engineering", 2026-10-24.
  <https://www.dbreunig.com/2026/10/24/the-state-of-context-engineering.html>
- `fail`: Breunig, "How Contexts Fail and How to Fix Them".
  <https://www.dbreunig.com/2025/06/22/how-contexts-fail-and-how-to-fix-them.html>
- `fix`: Breunig, "How to Fix Your Context".
  <https://www.dbreunig.com/2025/06/26/how-to-fix-your-context.html>
- `inertia`: Breunig, "Context Inertia".
  <https://www.dbreunig.com/2026/10/14/context-inertia.html>
- `weights`: Breunig, "Don't Fight the Weights".
  <https://www.dbreunig.com/2025/11/11/don-t-fight-the-weights.html>
- `gemini`: Gemini 2.5 technical report.
  <https://storage.googleapis.com/deepmind-media/gemini/gemini_v2_5_report.pdf>
  I did not open the PDF. Its quotes come from the Breunig posts above.
- `camassa`: Camassa and Shiller, "Do as I Say, Not as I Do".
  <https://arxiv.org/html/2605.20382v3>
- `memento`: Anthropic, Memento harness.
  <https://www.anthropic.com/research/self-replicating-ai>
- `fork`: Cai et al., "Fork-and-Flush".
  <https://arxiv.org/html/2610.07447v1>
- `sla`: Zhang et al., "Stateless Language Agents".
  <https://arxiv.org/html/2610.07625v1>
- `forget`: Tan et al., "Scaling Discovery Requires Forgetting".
  <https://arxiv.org/abs/2610.20563>
- `ragmcp`: Gan and Sun, RAG-MCP. <https://arxiv.org/abs/2505.03275>
- `lessismore`: "Less is More" (tool selection).
  <https://arxiv.org/abs/2411.15399>
- `lost`: "LLMs Get Lost in Multi-Turn Conversation".
  <https://arxiv.org/pdf/2505.06120>
- `provence`: Provence context pruner. <https://arxiv.org/abs/2501.16214>
- `multiagent`: Anthropic, multi-agent research system.
  <https://www.anthropic.com/engineering/built-multi-agent-research-system>
- `think`: Anthropic, think tool.
  <https://www.anthropic.com/engineering/claude-think-tool>
- `acontext`: Anthropic, effective context engineering.
  <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>

Claude Code docs:

- `cc-memory`: <https://code.claude.com/docs/en/memory.md>
- `cc-skills`: <https://code.claude.com/docs/en/skills.md>
- `cc-sub`: <https://code.claude.com/docs/en/sub-agents.md>
- `cc-hooks`: <https://code.claude.com/docs/en/hooks.md>
- `cc-ctx`: <https://code.claude.com/docs/en/context-window.md>
- `cc-model`: <https://code.claude.com/docs/en/model-config.md>
- `cc-best`: <https://code.claude.com/docs/en/best-practices.md>
- `cc-checkpoint`: <https://code.claude.com/docs/en/checkpointing.md>
- `cc-mcp`: <https://code.claude.com/docs/en/mcp.md>
- `cc-statusline`: <https://code.claude.com/docs/en/statusline.md>

API docs:

- `api-ctxedit`:
  <https://platform.claude.com/docs/en/build-with-claude/context-editing.md>
- `api-memory`:
  <https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool.md>
- `api-compact`:
  <https://platform.claude.com/docs/en/build-with-claude/compaction.md>

[article]: https://www.dbreunig.com/2026/10/24/the-state-of-context-engineering.html
[fail]: https://www.dbreunig.com/2025/06/22/how-contexts-fail-and-how-to-fix-them.html
[fix]: https://www.dbreunig.com/2025/06/26/how-to-fix-your-context.html
[inertia]: https://www.dbreunig.com/2026/10/14/context-inertia.html
[weights]: https://www.dbreunig.com/2025/11/11/don-t-fight-the-weights.html
[gemini]: https://storage.googleapis.com/deepmind-media/gemini/gemini_v2_5_report.pdf
[camassa]: https://arxiv.org/html/2605.20382v3
[memento]: https://www.anthropic.com/research/self-replicating-ai
[fork]: https://arxiv.org/html/2610.07447v1
[sla]: https://arxiv.org/html/2610.07625v1
[forget]: https://arxiv.org/abs/2610.20563
[ragmcp]: https://arxiv.org/abs/2505.03275
[lessismore]: https://arxiv.org/abs/2411.15399
[lost]: https://arxiv.org/pdf/2505.06120
[provence]: https://arxiv.org/abs/2501.16214
[multiagent]: https://www.anthropic.com/engineering/built-multi-agent-research-system
[think]: https://www.anthropic.com/engineering/claude-think-tool
[acontext]: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
[cc-memory]: https://code.claude.com/docs/en/memory.md
[cc-skills]: https://code.claude.com/docs/en/skills.md
[cc-sub]: https://code.claude.com/docs/en/sub-agents.md
[cc-hooks]: https://code.claude.com/docs/en/hooks.md
[cc-ctx]: https://code.claude.com/docs/en/context-window.md
[cc-model]: https://code.claude.com/docs/en/model-config.md
[cc-best]: https://code.claude.com/docs/en/best-practices.md
[cc-checkpoint]: https://code.claude.com/docs/en/checkpointing.md
[cc-mcp]: https://code.claude.com/docs/en/mcp.md
[cc-statusline]: https://code.claude.com/docs/en/statusline.md
[api-ctxedit]: https://platform.claude.com/docs/en/build-with-claude/context-editing.md
[api-memory]: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool.md
[api-compact]: https://platform.claude.com/docs/en/build-with-claude/compaction.md
