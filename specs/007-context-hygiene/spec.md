# Feature Specification: Agent Context Hygiene

**Feature Branch**: `007-context-hygiene`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: `docs/context-engineering-claude-code-research.md`,
a research report mapping Drew Breunig's "The State of Context Engineering"
(2026-10-24) onto this repository's Claude Code setup. The report finds that
the setup is strong on augmentation, offloading, at-source pruning and
deterministic enforcement, and lists eleven prioritized gaps: no context-size
signal, an auto-compaction window left near the top of the 1M window, no
handoff-and-reset workflow, recommended `cavecrew-*` subagents that are not
installed, rtk's "No hook installed" banner in every shell result, auto memory
running beside `bd remember`, every MCP server loaded in every project, a
skill listing full of skills irrelevant to the current repository, unbounded
kagi/context7 output, duplicated beads guidance, and a prose-only
TodoWrite/TaskCreate ban. This feature closes those gaps.

## Clarifications

### Session 2026-10-27

- Q: When the agent tries to use its built-in task-list tools (TodoWrite,
  TaskCreate), should a rule block them, or should the prose ban be dropped?
  → A: Deny both tools with a rule; keep a one-line pointer to `bd` in the
  project instructions.
- Q: What should happen to a web-search or docs-lookup result larger than 10K
  tokens? → A: Cut it to 10K tokens and save the full result to a file the
  agent can read on request. Results of 10K tokens or less pass through
  unchanged. (The compressing proxy cannot do this: it leaves tool results
  untouched.) Refined by the next answer: the cut is the harness's own
  save-to-file with a short preview, not a 10K-token excerpt.
- Q: Should results over 10K tokens be handled by the harness's built-in
  "save to file, show a preview", with the limit lowered to 10K for all MCP
  tools, or by a custom hook for kagi and context7 that keeps the first 10K
  tokens visible? → A: Built-in, with the MCP output limit set to 10K tokens
  for all MCP tools.

## User Scenarios & Testing *(mandatory)*

The user is the single owner of this workstation configuration. They run
coding-agent sessions daily across several repositories on several machines.
"Context" below means everything the agent holds in its working window for a
session: instructions, tool descriptions, conversation and tool output.

### User Story 1 - See how large the agent's context has grown (Priority: P1)

During a long session the user wants to notice, without asking, when the
context has passed the size at which agents start repeating old patterns and
ignoring instructions. The agent's status line shows the current context size
next to the mode badge. Below the first warning point it looks
neutral. Past the first warning point (200K tokens) it changes appearance, and
past a second, stronger point (400K tokens) it changes again.

**Why this priority**: Every other reset-related improvement depends on the
user knowing when a reset is due. It is cheap, deterministic, and on its own
turns Breunig's main advice ("reset at about 200K") into something visible.

**Independent Test**: Start a session, confirm a small size is shown in the
neutral style. Feed the agent enough material to pass 200K, confirm the
warning style. Pass 400K, confirm the strong-warning style. Confirm the mode
badge still appears in all three states.

**Acceptance Scenarios**:

1. **Given** a session after its first response, **When** the status line
   renders, **Then** it shows the mode badge (if active) and a context size in a human-readable unit (for
   example `38K`), in the neutral style.
2. **Given** a session whose context is above 200K and at most 400K tokens,
   **When** the status line renders, **Then** the size appears in the warning
   style.
3. **Given** a session whose context is above 400K tokens, **When** the status
   line renders, **Then** the size appears in the strong-warning style.
4. **Given** the agent harness supplies no context-size data (for example the
   very first render), **When** the status line renders, **Then** it shows the
   mode badge alone and does not show an error.

---

### User Story 2 - Hand off work and reset the conversation (Priority: P1)

The user notices the context is large, or that the agent keeps pursuing a
dead end. They invoke a single handoff command. The agent writes a short
note to the issue currently being worked on: what it tried, what failed and
why, and what to try next. It then tells the user the note is saved and that
they can now clear the conversation. After the user clears it, the new
session starts with the tracker's usual priming, so the agent can find the
issue and read the note without the old conversation.

**Why this priority**: Four independent research results converge on "throw
the conversation away, keep the work". Compaction alone keeps the model's
commitment to a stale hypothesis. This is the single most effective remedy the
report identifies, and only half of it (re-priming after a clear) exists today.

**Independent Test**: In a session with an in-progress issue, invoke the
handoff command. Confirm the issue now carries a note with the three parts.
Clear the conversation and ask the new session "what was I doing?". Confirm it
answers from the note.

**Acceptance Scenarios**:

1. **Given** exactly one issue in progress, **When** the user invokes the
   handoff command, **Then** a note with "tried", "failed" and "next" parts is
   appended to that issue, and existing notes on it are kept.
2. **Given** no issue in progress, **When** the user invokes the handoff
   command, **Then** the agent asks which issue to attach the note to, or
   offers to create one, and writes nothing until the user answers.
3. **Given** several issues in progress, **When** the user invokes the handoff
   command, **Then** the agent asks which one the note belongs to.
4. **Given** the agent itself, unprompted, **When** it decides what to do
   next, **Then** it never invokes the handoff command on its own; only the
   user starts it.
5. **Given** the note has been written and the conversation cleared, **When**
   the new session starts, **Then** the issue tracker's priming runs as it
   does today and the new session can locate the note.

---

### User Story 3 - Cap how large the context can grow before summarization (Priority: P2)

The user wants a ceiling on the worst case when they miss the warning. The
agent summarizes its own conversation automatically at a fixed, lower size
instead of near the top of its maximum window.

**Why this priority**: It bounds distraction when the habit in Story 2 is not
followed. It is lower than Stories 1–2 because the research shows
summarization alone does not undo a stale hypothesis, and each summarization
is itself an expensive request.

**Independent Test**: Inspect the effective agent settings on a built
configuration and confirm the automatic-summarization point is 400K tokens on
every machine.

**Acceptance Scenarios**:

1. **Given** the configuration is deployed, **When** a session grows past 400K
   tokens, **Then** the agent summarizes the conversation automatically.
2. **Given** the user overrides the point for one session by hand, **When**
   that session runs, **Then** the manual override wins for that session only.

---

### User Story 4 - Remove instructions that contradict the installed tools (Priority: P2)

The user wants the agent's standing instructions to match what is actually
installed and enforced, so the agent is never told to use a tool that does not
exist, never has two memory stores, and is not asked in prose to do what a
rule could enforce.

**Why this priority**: Each contradiction is a small, permanent tax on every
session in every repository. Fixing them is low-effort and removes the
"context clash" and "fighting the weights" failure modes the report found.

**Independent Test**: Start a session in this repository and in one other.
Confirm the list of available helper agents matches every helper agent the
instructions recommend; confirm only one memory mechanism is active; confirm
the task-list tools the instructions forbid are either blocked by a rule or no
longer forbidden.

**Acceptance Scenarios**:

1. **Given** the global instructions recommend the `cavecrew-investigator`,
   `cavecrew-builder` and `cavecrew-reviewer` helper agents, none of which is
   installed, **When** a session starts, **Then** the global instructions no
   longer mention any `cavecrew-*` agent, and delegation guidance names only
   helper agents that are available.
2. **Given** the configuration is deployed, **When** a session runs, **Then**
   the harness's built-in automatic memory is off and the issue tracker's
   memory is the only persistent memory store.
3. **Given** the project instructions say not to use the harness's built-in
   task-list tools, **When** the configuration is deployed, **Then** the
   deployed settings deny TodoWrite, TaskCreate, TaskGet, TaskList and
   TaskUpdate, none of them appears in a session's tool list, and the project
   instructions carry a one-line pointer to the issue tracker instead of the
   prose ban.
4. **Given** beads guidance currently reaches the agent from more than one
   source, **When** the duplication is reviewed, **Then** each beads rule the
   agent sees appears in one source only, or any remaining duplicate is
   documented as intentional.

---

### User Story 5 - Stop noise in every tool result (Priority: P2)

The user wants shell results to contain only the command's own output. Today
every shell result starts with one or two copies of a warning that the output
compressor's hook is missing, although the compressor is wired in through a
different mechanism and works.

**Why this priority**: The banner appears in every shell result of every
session. It is pure noise in the most frequently repeated content in context.

**Independent Test**: Run several shell commands in a session. Confirm none of
the results contains the "No hook installed" banner and that output is still
compressed.

**Acceptance Scenarios**:

1. **Given** the configuration is deployed, **When** the agent runs any shell
   command, **Then** the result contains no "No hook installed" banner.
2. **Given** the banner is suppressed, **When** the agent runs a command the
   compressor normally shortens, **Then** the output is still shortened.

---

### User Story 6 - Load only the tools and skills relevant to the repository (Priority: P3)

The user wants each session to start with tool servers and skill descriptions
that match the repository at hand. Device-automation and browser-automation
servers should not appear in a Nix configuration repository, and design-system
or codebase-understanding skills should not crowd the skill list where they
are unused. Repositories that need the servers can still turn them on; the
user can still invoke any hidden skill by name.

**Why this priority**: Tool search already hides most tool definitions, so the
remaining cost is server instruction blocks and skill descriptions. The gain
is real but smaller than Stories 1–5.

**Independent Test**: Start a session in this repository; confirm the
device-automation and browser-automation servers are absent and the
design-system skills do not appear in the automatic skill list. Enable one of
those servers for a single other repository with one entry in that
repository's `.claude/settings.local.json`; start a session there and confirm
it is present.

**Acceptance Scenarios**:

1. **Given** a repository with no per-project opt-in, **When** a session
   starts, **Then** the mobile device-automation and browser-automation tool
   servers are not connected.
2. **Given** a repository that opts in to one of those servers, **When** a
   session starts there, **Then** that server is connected.
3. **Given** the Oslo kommune design-system skills and the
   codebase-understanding skills, **When** a session lists skills for
   automatic use, **Then** they are absent from the automatic listing and
   remain invocable by the user by name.
4. **Given** the cavekit spec-workflow skills (`spec`, `build`, `check`,
   `backprop`), **When** a session lists skills, **Then** they are listed by
   name only and one can still invoke another.
5. **Given** this repository's own `speckit-*` skills, **When** a session
   starts here, **Then** they are listed as before.
6. **Given** the skill listing has been pruned, **When** the skill-listing
   budget is returned to the harness default (1% of context), **Then** no
   still-listed skill loses its description to the budget.

---

### User Story 7 - Bound the size of tool-server results (Priority: P3)

The user wants no single tool-server result to put more than 10K tokens into
the conversation. Today one web-page extraction can return a whole talk
transcript. A result over the bound is kept out of the conversation: the
agent gets a short preview and the path of a file holding the full result,
and reads the file only when it needs the content.

**Why this priority**: Large results happen mostly in research sessions, so
this matters less day to day than Stories 1–6.

**Independent Test**: In a session, extract a long web page, look up a large
library's docs and fetch a large diff. Confirm each result over 10K tokens
arrives as a preview plus a file path, and that a short result arrives
unchanged.

**Acceptance Scenarios**:

1. **Given** the configuration is deployed, **When** any tool server returns
   a text result of 10K tokens or less, **Then** it reaches the agent
   unchanged.
2. **Given** the configuration is deployed, **When** a tool server returns a
   text result larger than 10K tokens, **Then** the agent receives a short
   preview and the path of a file holding the full result instead of the
   result itself.
3. **Given** a result was saved to a file, **When** the agent needs the rest,
   **Then** it can read the full result from the named file.
4. **Given** a tool declares its own larger result limit, **When** it returns
   a large result, **Then** the tool's own limit applies; planning records
   which installed tools do this.

---

### Edge Cases

- The harness changes the name or shape of the context-size data the status
  line reads: the status line falls back to the mode badge alone rather than
  printing an error or a wrong number.
- The handoff command runs in a repository without an issue tracker: the agent
  says the note cannot be stored there and offers to print it in the
  conversation instead.
- The handoff note would be very long: it is kept to a short summary (target:
  under 20 lines), since its value is that a fresh session can read it cheaply.
- A user-level manual override of the summarization point exists in the
  environment: the manual value wins, as documented by the harness.
- A repository's own project settings already enable a server that is now
  off by default: the project setting wins.
- Turning off built-in automatic memory leaves existing memory files on disk:
  they are left untouched, not deleted; they simply stop being loaded.
- A skill pruned from the automatic listing is invoked by name by the user: it
  still runs.
- A saved result's file must be readable by the agent. The harness writes it
  to the session's own results folder and cleans it up with the session.
- A tool returns an error result rather than a successful one: the harness's
  separate error rule applies (first and last 5,000 characters kept), and
  this feature does not change it.
- The output compressor is updated upstream and its banner text changes: the
  suppression does not depend on matching the exact banner wording, or a build
  check catches the change.

## Requirements *(mandatory)*

### Functional Requirements

**Context-size signal**

- **FR-001**: The agent status line MUST show the current context size next to
  the mode badge (when a mode is active) on every machine. Context size means
  the input tokens in the context window, as reported by the harness after
  the most recent response.
- **FR-002**: The size display MUST have three visually distinct states:
  neutral at or below 200K tokens, warning above 200K up to 400K, strong
  warning above 400K.
- **FR-003**: When context-size data is missing, zero or unreadable, the
  status line MUST show the mode badge alone (or nothing, if no mode is
  active) and MUST NOT show an error.

**Handoff and reset**

- **FR-004**: The user MUST be able to start a handoff with one command. Its
  name MUST NOT collide with the already-installed `handoff` and
  `claude-handoff` skills, which behave differently.
- **FR-005**: The handoff MUST append a note with three labelled parts (tried,
  failed with reason, next step) to the notes of the issue currently in
  progress, without removing earlier notes. It MUST leave the issue's status
  unchanged (in progress), so the next session finds it.
- **FR-006**: When zero or several issues are in progress, the handoff MUST
  ask the user which issue to use before writing anything.
- **FR-007**: The handoff MUST NOT be started by the agent on its own
  initiative.
- **FR-008**: After writing the note, the handoff MUST tell the user it is
  safe to clear the conversation. It MUST NOT clear it itself.
- **FR-009**: A session started after a clear MUST receive the issue
  tracker's priming, as it does today, so the note can be found.

**Automatic summarization**

- **FR-010**: The automatic-summarization point MUST be set to 400K tokens, or
  the model's context window if that is smaller, for all models on every
  machine, declared in the shared configuration.
- **FR-011**: A per-session override (the in-session command, a launch flag,
  or an environment variable in the launch shell) MUST take precedence over
  the configured point. Persisting a per-model value from inside a session is
  not supported, because user settings are declarative and read-only.

**Instruction consistency**

- **FR-012**: The standing instructions and installed skill descriptions MUST
  NOT recommend the uninstalled `cavecrew-*` helper agents; the `cavecrew`
  skill that recommends them is removed. Every helper agent the instructions
  still name MUST be available in a session (this also removes the stale
  `code-review-graph` mention). Installing the `cavecrew-*` agents is out of
  scope.
- **FR-013**: The harness's built-in automatic memory MUST be disabled, so the
  issue tracker's memory is the only persistent memory store.
- **FR-014**: The harness's built-in task-list tools (TodoWrite, TaskCreate,
  TaskGet, TaskList and TaskUpdate) MUST be denied by a rule. TaskStop,
  TaskOutput and SendMessage MUST stay allowed. The prose ban MUST shrink to a
  one-line pointer to the issue tracker, placed outside any block the issue
  tracker regenerates.
- **FR-015**: Beads guidance that reaches the agent from more than one source
  MUST be reduced to one source per rule, or each remaining duplicate MUST be
  recorded as intentional with its reason.

**Output noise and size**

- **FR-016**: Shell results MUST NOT contain the output compressor's "No hook
  installed" banner.
- **FR-017**: Suppressing the banner MUST NOT disable output compression.
- **FR-018**: The harness's tool-server output limit MUST be set to 10K
  tokens for all tool servers on every machine, so that larger text results
  are saved to a file and replaced by a preview and the file path. Results
  of 10K tokens or less MUST pass through unchanged. No custom result
  rewriting is added.

**Per-repository loadout**

- **FR-019**: The mobile device-automation and browser-automation tool servers
  MUST be off by default for Claude Code on every machine, declared in this
  repository. A repository opts in with one entry in its own
  `.claude/settings.local.json` (personal) or `.claude/settings.json`
  (shared). Opencode keeps both servers as today.
- **FR-020**: Domain-specific user skills MUST leave the automatic listing or
  be listed by name only, and MUST remain invocable by the user by name: the
  Oslo kommune design-system skills (`punkt-*`) and the codebase-understanding
  skills (`understand*`) are hidden from automatic use; the cavekit
  spec-workflow skills (`spec`, `build`, `check`, `backprop`) are listed by
  name only, because they invoke each other. The `speckit-*` project skills
  stay on. The beads plugin's slash commands become user-only.
- **FR-021**: The skill-listing budget MUST be returned to the harness default
  once FR-020 is met, provided no still-listed skill loses its description
  (checked with the harness's diagnostics: no over-budget warning).

**Cross-cutting**

- **FR-022**: Every change MUST be declared in the repository's configuration
  and MUST apply identically on every machine in the machine registry
  (currently four); no manual per-machine step is allowed. The per-repository
  opt-in of FR-019 lives in the opting-in repository by design.
- **FR-023**: Every configurable value introduced (warning points,
  summarization point, servers off by default) MUST fail at configuration
  build time when given an invalid value.
- **FR-024**: Decisions with lasting consequences (single memory store, reset
  workflow, per-repository server loadout) MUST be recorded as an ADR, and new
  terms (for example "handoff note") MUST be added to `GLOSSARY.md`.

### Key Entities

- **Context size**: the number of tokens the agent currently holds for the
  session. Read-only; supplied by the agent harness.
- **Warning point**: a context size at which the status line changes state.
  Two values: 200K and 400K.
- **Summarization point**: the context size at which the agent automatically
  summarizes its conversation. One value: 400K.
- **Handoff note**: a short note attached to an issue, with "tried", "failed"
  and "next" parts, written at a reset. Lives with the issue, not in the
  conversation.
- **Tool server loadout**: the set of tool servers connected for a session,
  derived from a global default plus a per-repository opt-in.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of sessions the user can read the current context size
  from the status line without typing a command.
- **SC-002**: A handoff, from invoking the command to a new session that can
  state the task and next step, takes under 2 minutes.
- **SC-003**: No session's conversation grows past 400K tokens without being
  summarized.
- **SC-004**: Zero shell results in a sampled session contain the "No hook
  installed" banner (today: every result).
- **SC-005**: Zero helper agents are recommended in the standing instructions
  that are not available in the session.
- **SC-006**: In this repository, the number of connected tool servers drops
  by at least 2, and the number of skills and commands listed with a
  description for automatic use drops by at least 20 on every machine,
  compared with the 2026-10-27 baseline (taken on dig-laptop).
- **SC-007**: No single tool-server text result placed in the conversation
  exceeds 10K tokens, except from tools that declare their own larger limit,
  and every saved result's full text is recoverable from its file.
- **SC-008**: The configuration still builds and passes its fast check for
  every machine in the registry after the change.

## Assumptions

- The 200K and 400K points come from the research report and Breunig's own
  practice. They are starting values and may be tuned later without
  re-specifying.
- The issue tracker's existing priming on a cleared session (SessionStart
  `clear`) works as the beads plugin documents. Planning confirmed the hook
  file; a live check after `/clear` is still part of the quickstart.
- Denying the task-list tools also disables the shared task list of the
  experimental agent teams, which then coordinate through messages only. This
  is accepted: beads is the task tracker. On the default model (Opus 5.x)
  these tools are not offered at all, so the deny rule mainly covers older
  models and subagents.
- The servers off by default are only mobile device automation and browser
  automation. The GitHub server stays on, because this user works in GitHub
  repositories daily.
- Plugin-provided skills cannot be pruned through the harness's per-skill
  overrides. Every FR-020 group is a user skill, so overrides cover them; the
  build-time filter is needed only for the beads plugin's commands.
- The compressor's banner has an official switch (rtk 1.0.1:
  `RTK_SUPPRESS_HOOK_WARNING`). It appears because rtk recognises only its own
  hook command, and the sandbox's read-only data directory defeats its
  once-a-day rate limit. The sandbox is not to be widened for it.
- The research report's suggestion to wrap kagi and context7 in the
  compressing proxy does not bound result size: the proxy (`caveman-shrink`
  0.1.1) rewrites only tool, prompt and resource descriptions and passes tool
  results through unchanged. FR-018 instead uses the harness's own limit.
  Per the Claude Code MCP docs (checked 2026-10-27), a successful text result
  over `MAX_MCP_OUTPUT_TOKENS` (default 25,000) or over 50,000 characters is
  saved to the session's `tool-results` folder and replaced by its path. A
  tool that declares `anthropic/maxResultSizeChars` uses its own character
  limit instead. Planning checked: neither kagi (kagimcp) nor context7-mcp
  4.4.4 declares one.
- Running the instruction audit once by hand (`/doctor prompt-audit`) is an
  input to FR-015, not a recurring feature.
- Periodic review or expiry of tracker memories ("strategic forgetting") is
  out of scope; the report could not confirm whether the tracker supports
  expiry. A follow-up issue will track it.
- Automating the reset (a timed loop that clears itself) is out of scope; the
  report marks it unverified.
