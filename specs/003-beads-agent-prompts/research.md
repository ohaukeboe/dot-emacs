# Research: Prompt the Coding Agent from a Beads Issue

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Each entry records one decision the plan depends on, why it was made, and what
was rejected. Facts about `claude-code-ide` were read from the pinned flake input
(`inputs.claude-code-ide-src`, `/nix/store/2ln0l5s9…-source/claude-code-ide.el`),
not from an older copy in the store — an older copy lacks
`claude-code-ide--resolve-session` entirely.

## R1 — Where the agent integration lives

**Decision**: `beads.el` knows nothing about `claude-code-ide`. It exposes two
variables, `beads-agent-available-function` and `beads-agent-send-function`, and
`config.org` sets them to thin adapters over `claude-code-ide`. With both nil
(the default), the agent entries are unavailable and the commands say that no
agent is configured.

**Rationale**:

- `beads.el` is a self-contained package with its own ERT suite
  (`nix build .#test-beads`), whose closure is Emacs + Magit only. Pulling
  `claude-code-ide` into it would drag a WebSocket server, a terminal backend and
  a flake input into the test build for the sake of four function calls.
- The adapter has to call `claude-code-ide`'s private `--` functions (R2). The
  config already has a paragraph that says those internals are leaned on and must
  be re-checked when bumping the input; the adapter belongs under it, not in a
  package that would otherwise have no reason to know.
- With the functions injectable, the tests substitute a recorder and assert the
  exact text, the submit flag and the no-op cases — the parts the spec actually
  constrains.

**Alternatives considered**:

- *`(require 'claude-code-ide)` inside `beads.el`, soft-guarded with
  `declare-function`.* Rejected: the test build would still need the package to
  exercise anything, and the private-API coupling would move into a file whose
  commentary promises "a repository without one gets no section and pays nothing".
- *A generic agent abstraction (`cl-defgeneric` over backends).* Rejected: one
  backend exists. Two variables are the smallest seam that still lets the tests
  in.

## R2 — Choosing the session and delivering the text

**Decision**: lift the existing `my/magit-review--paste` (config.org, Magit review
block) into the Claude Code section as `my/claude-code-ide-paste TEXT SUBMIT`,
unchanged in behaviour, and make both the review hand-off and beads call it. Add
next to it `my/claude-code-ide-session-p`, which is non-nil when
`claude-code-ide` is loaded and
`(claude-code-ide-mcp--sessions-for-project (claude-code-ide--get-working-directory))`
is non-empty.

**Rationale**:

- `claude-code-ide--resolve-session 'auto` already implements the spec's "several
  sessions" edge case and the user's established habit from `@`: one session or
  one visible session is taken without asking, otherwise the most recently used
  one is taken and named in the echo area, and a prefix argument always asks.
  Reusing it is FR-014 for free, and is the "same session choice applies"
  assumption of the spec made literal.
- The paste helper already handles each terminal backend's paste primitive
  (`ghostel-paste-string`, `vterm-send-string` with paste, `eat` yank), which is
  what makes multi-line text arrive as one input rather than as several submitted
  lines. The explore prompt is multi-line (R5).
- Two copies of that `pcase` would be Principle IV's divergence waiting to happen.
- `--get-working-directory` is `project-root` of `default-directory`. In the Magit
  status buffer and in a `beads-show-mode` buffer `default-directory` is the
  repository root (the show buffer sets it explicitly), so the session found is
  this repository's.

**Alternatives considered**:

- *`claude-code-ide-send-prompt`*, the public command. Rejected: it uses
  `claude-code-ide--terminal-send-string`, which types rather than pastes, so a
  newline in the explore prompt would submit half of it; and it ignores the
  multi-instance resolution, always addressing the default buffer name.
- *The MCP `at-mentioned` channel.* Rejected: it inserts a file/selection mention,
  not free text, and cannot submit.

## R3 — Quick prompt: what is inserted, and how focus is given

**Decision**: the quick prompt pastes `beads-agent-quick-prompt-format` formatted
with the ids joined by `", "`. Default: `"Beads issue %s: "`, the same for one
id or several — a plural variant is not worth a second option. It is pasted
with SUBMIT nil, then the agent buffer is shown and selected: its window if it has
one, otherwise `pop-to-buffer`. This is the same sequence `my/magit-review-send`
already performs for its no-submit variant.

**Rationale**:

- The prefix says what the identifier is. An agent in this repository knows the
  `dot-emacs-` prefix from `AGENTS.md`, but the quick prompt should work in any
  repository with a tracker, whose prefix the agent has no reason to recognise.
- Ending in `": "` leaves the terminal cursor where the developer's first word
  goes (FR-002).
- The prefix never starts with `/`, `!` or `#`, each of which Claude Code treats
  specially at the start of an input. A test asserts that of the default.
- FR-003 (keep unsent text) needs no code: a paste inserts at the terminal's
  cursor and never clears the input line. What it does mean is that the
  reference lands wherever that cursor is — normally the end of the input.
  Recorded as a limitation in the contract rather than worked around: moving the
  cursor to the end would require sending terminal-specific key sequences into a
  line editor this feature does not own.

**Alternatives considered**:

- *Only the bare id.* Rejected for the cross-repository reason above.
- *`@`-mention of `.beads/…`*. Rejected: the database is Dolt, not a readable
  file, and the spec's assumption is that the agent reads the issue through `bd`.

## R4 — Explore: submission and window handling

**Decision**: explore pastes the expanded explore prompt with SUBMIT t, does not
select or display the agent buffer, and reports
`"Sent explore prompt for <id> to <buffer name>"`. The paste helper's existing
0.1 s pause between paste and return is kept.

**Rationale**: FR-016 asks for the developer's window to stay put. The review
hand-off already demonstrates that pasting then sending return with the 0.1 s
pause is reliable with the ghostel backend this configuration uses.

**Alternatives considered**: *show the agent buffer after sending.* Rejected by
FR-016; the developer can bring it up with their usual `C-c o c`.

## R5 — The explore prompt: wording, placeholder, fallback

**Decision**: `beads-agent-explore-prompt` is a string expanded with
`format-spec` and the spec `%i` for the issue id, with `format-spec`'s
IGNORE-MISSING argument so a stray `%` never signals. When the expanded string
does not contain the id, `"Beads issue <id>:\n\n"` is prepended (FR-010). The
default text is fixed in [contracts/explore-prompt.md](./contracts/explore-prompt.md).

**Rationale**:

- `format-spec` with a named spec is the Emacs convention for user-editable
  templates (`mode-line`, `display-time-format`, Magit's own formats), and a
  named `%i` survives the developer reordering the text, which positional
  `format` `%s` would not if they ever wanted the id twice.
- The prompt asks the agent to read the issue *through `bd show`*, so that its
  relations and comments come with it (FR-006) and so that nothing about the
  issue is pasted into the prompt (spec assumption).
- The "do not implement" instructions are enumerated rather than summarised
  (FR-008): no file changes, no tracker changes by verb, no commits, no skill or
  workflow. The review of SC-003 runs against exactly these clauses.
- It closes by telling the agent to stop and wait, and says why — the developer
  chooses how the work is done — because an instruction with its reason is
  followed more reliably than a bare prohibition.

**Alternatives considered**:

- *`{id}` string replacement.* Workable, but a second template syntax in a
  configuration that already uses `format-spec`.
- *Store the prompt as a skill file for the agent instead.* Rejected: the user
  asked that the agent be free to choose skills *afterwards*; a skill that must be
  installed for explore to work is a second moving part, and the prompt would no
  longer be editable where the command is.

## R6 — Target resolution and the no-issue case

**Decision**: both commands take their ids from `beads--issues-at-point`, which
already covers the Magit section at point, the Magit region and the
`beads-show-mode` buffer. When it returns nil they signal
`user-error "No beads issue at point"` — they do **not** fall back to
`beads--read-issue` as `beads--targets` does for the other commands. Explore
signals `user-error` when given more than one id.

**Rationale**: the spec's edge case asks for "say so and do nothing". Reading an
issue with completion is reasonable for claim or close, whose outcome is visible
in the tracker; for a prompt sent to an agent, a mis-chosen completion is sent
before it is noticed. Checking the issue and the session before any paste also
gives FR-013 its "unchanged" guarantee: every refusal happens before the first
byte reaches the terminal.

## R7 — Transient placement and availability

**Decision**: a new `Agent` column in `beads-dispatch` with `i` "Prompt" →
`beads-agent-prompt` and `e` "Explore" → `beads-agent-explore`, both
`:inapt-if-not beads--agent-available-p`. `i` and `e` are unused in the
transient today (`k c m a 0-4 p b d B n RET`).

**Rationale**: `:inapt-if-not` rather than `:if` matches the Relations column's
existing, commented choice — the menu keeps its shape. The predicate calls
`beads-agent-available-function`, which in the adapter is a hash-table lookup and
costs nothing measurable while the transient redraws.

**Alternatives considered**: *global keys outside the transient.* Rejected, as for
the relation commands: `#` is the established entry point and the spec only asks
for the menu.

## R8 — Testing

**Decision**: extend `beads-test.el` with cases that let-bind both agent
variables to recorders, run each command from a Magit status buffer fixture and
from a `beads-show-mode` buffer, and assert the recorded `(TEXT . SUBMIT)` pairs
and the absence of any call in the refusal cases. The claude-code-ide adapters are
verified by the manual steps in [quickstart.md](./quickstart.md); SC-003 is a
manual measurement by definition.

**Rationale**: the test build stays Emacs + Magit (R1). Everything the spec
constrains about *what is sent, when, and when nothing is* sits on the beads side
of the seam.
