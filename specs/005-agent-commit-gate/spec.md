# Feature Specification: Agent Commit Gate

**Feature Branch**: `005-agent-commit-gate`

**Created**: 2026-10-23

**Status**: Draft

**Input**: User description: (none given with the command; derived from the
research request of 2026-10-23 and its findings in
`docs/claude-commit-gate-magit-research.md`) "Is it possible to make the block
for allowing Claude to create commits easily toggleable? I am thinking of also
having a setting where it is allowed to create commits inside worktrees that
are created by Claude, but to still have it prompt me when creating commits in
the current branch. Also, instead of a prompt which asks whether it can perform
the commit, I would like it to open the commit message in Emacs Magit. This way
I would be able to review the commit message and maybe alter it."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review and edit the agent's commit in the editor (Priority: P1)

The agent has staged changes in the user's own checkout and asks to commit them
with a message it wrote. Instead of a yes/no permission prompt in the terminal,
the user's editor opens its normal commit view: the staged diff next to the
agent's message, which the user can edit. The user either finishes the commit
or cancels it from the editor. The agent is then told the outcome — committed
(with the commit id and subject) or not committed (with the reason) — and does
not try to run the same commit again.

**Why this priority**: This is the change the user wants most. The current
prompt shows only the command text, so the user cannot see the diff next to the
message, and cannot fix a poor message without rejecting the commit and
explaining in chat.

**Independent Test**: In the user's checkout, ask the agent to stage one file
and commit it. Confirm the editor opens with the staged diff and the agent's
message. Edit the subject and finish: the history has one new commit with the
edited subject, and the agent reports that commit id. Repeat and cancel
instead: no commit is created, and the agent reports that the user declined.

**Acceptance Scenarios**:

1. **Given** the review mode is active and changes are staged, **When** the
   agent requests a commit with a message, **Then** the editor shows the staged
   changes and the agent's message for editing, and no commit exists until the
   user finishes.
2. **Given** the review is open, **When** the user edits the message and
   finishes, **Then** exactly one commit is created with the edited message and
   exactly the changes staged at that moment, and the agent receives the
   commit id and subject.
3. **Given** the review is open, **When** the user cancels or leaves the message
   empty, **Then** no commit is created and the agent is told the commit was
   declined and must ask before trying again.
4. **Given** the editor is not running or cannot be reached, **When** the agent
   requests a commit, **Then** the request falls back to the ordinary
   permission prompt rather than committing or failing silently.
5. **Given** nothing is staged, **When** the agent requests a commit, **Then**
   the request is refused with "nothing staged" and no review opens.

---

### User Story 2 - Switch the gate's behaviour quickly (Priority: P2)

The user wants to change how agent commits are handled without editing and
rebuilding the configuration: for example to fall back to the plain prompt for
one session, to block agent commits entirely while doing something sensitive,
or to turn the editor review on again. A persistent default is declared in the
configuration; a quick override is available from the editor and for a single
session at launch. The agent itself cannot change either.

**Why this priority**: The review mode is only pleasant if it is easy to turn
off when it gets in the way, and easy to tighten when needed. It is useful on
its own even with only the existing prompt behaviour.

**Independent Test**: With the declared default set to the plain prompt, set
the quick override to "editor review" from the editor and ask the agent to
commit: the editor review opens. Clear the override: the next commit request
shows the plain prompt. Ask the agent to change the override itself: the
attempt is refused.

**Acceptance Scenarios**:

1. **Given** a declared default mode, **When** no override is set, **Then** the
   declared default applies.
2. **Given** the user sets an override from the editor, **When** the agent next
   requests a commit, **Then** the override applies without a rebuild or a
   restart of the agent session.
3. **Given** a session started with a launch-time override, **When** the agent
   requests a commit in that session, **Then** the launch-time override wins
   over both the editor override and the declared default.
4. **Given** any mode, **When** the agent tries to change the override or the
   declared default by any of its own tools, **Then** the change is refused.
5. **Given** the mode "blocked", **When** the agent requests a commit, **Then**
   the request is refused with a reason saying agent commits are disabled.

---

### User Story 3 - Free commits in the agent's own worktrees (Priority: P3)

When the agent works in an isolated worktree that it created itself, on its own
branch, the user is happy for it to commit without asking, because nothing
lands on the user's branches until the user merges it. Commits in the user's own
checkout, in worktrees the user made, or on any of the user's branches still go
through the gate. This is a separate setting that is off by default.

**Why this priority**: It removes friction for longer autonomous or parallel
tasks, but it depends on the gate being configurable (Story 2) and is only safe
when the "agent's own worktree" test is strict.

**Independent Test**: Turn the setting on. Start an isolated agent task in its
own worktree and ask it to commit: the commit is made with no prompt and no
review. In the same session ask for a commit in the main checkout: the gate
applies. Create a worktree by hand and ask for a commit there: the gate applies.

**Acceptance Scenarios**:

1. **Given** the setting is on, **When** the agent commits inside a worktree it
   created, on that worktree's own branch, **Then** the commit proceeds with no
   prompt or review.
2. **Given** the setting is on, **When** the agent commits in the user's main
   checkout, **Then** the main-checkout mode applies.
3. **Given** the setting is on, **When** the agent commits in a worktree the user
   created, or in its own worktree after switching to a different branch,
   **Then** the main-checkout mode applies.
4. **Given** the setting is on, **When** the commit command points git at a
   different directory or repository than the one it runs in, or cannot be
   understood, **Then** it is treated as the main checkout.
5. **Given** the setting is off, **When** the agent commits in its own worktree,
   **Then** the main-checkout mode applies.

---

### Edge Cases

- The review stays open longer than the allowed wait: the review is withdrawn,
  no commit is made afterwards even if the user later finishes the stale
  review, and the agent is told it timed out.
- The agent session is interrupted while a review is open: a later "finish" on
  that review must not create a commit the agent was never told about.
- Two commit requests arrive at once (main session and a background agent):
  each gets its own review, and outcomes are not mixed up.
- The commit is rejected by a repository commit check (pre-commit or message
  hook): reported to the agent as "not committed" with the reason.
- The request uses a form the review cannot represent faithfully (amend,
  reusing another commit's message, skipping commit checks): falls back to the
  ordinary permission prompt.
- The same command both stages files and commits, or commits with options that
  stage implicitly: still refused, as today, in every mode — including free
  worktree mode.
- The gating machinery fails or is killed before it decides: the commit still
  needs explicit approval; it never proceeds unapproved.
- The agent's commit message contains several paragraphs or is given from a
  file: the review shows the complete message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support these modes for agent commits in the
  user's checkouts: "prompt" (today's permission prompt), "editor review", and
  "blocked".
- **FR-002**: The system MUST support a separate setting for the agent's own
  worktrees with values "free" and "gated", default "gated".
- **FR-003**: The persistent default for both settings MUST be declared in the
  configuration, with invalid values rejected when the configuration is built.
- **FR-004**: The user MUST be able to override the main-checkout mode from the
  editor, globally or for one repository, effective on the next commit request
  without a rebuild or session restart.
- **FR-005**: The user MUST be able to override the mode for a single agent
  session when starting it.
- **FR-006**: Precedence MUST be: launch-time override, then per-repository
  editor override, then global editor override, then declared default.
- **FR-007**: The agent MUST NOT be able to change any override or the declared
  default through its shell, its file-editing tools, or the repository's
  configuration.
- **FR-008**: In "editor review" mode, the system MUST open the editor's commit
  view showing the staged changes and the agent's full proposed message, editable.
- **FR-009**: In "editor review" mode, the commit MUST be created only when the
  user finishes the review, and MUST contain exactly the changes staged at that
  moment and the message as the user left it.
- **FR-010**: After a review, the agent MUST receive the outcome: the commit id
  and subject on success, or "not committed" with the reason on cancel, empty
  message, failed commit check, or timeout.
- **FR-011**: After a review the agent's original commit command MUST NOT also
  run, so a single request never produces two commits.
- **FR-012**: The system MUST fall back to the ordinary permission prompt when
  the editor is unreachable or the request uses a commit form the review
  cannot represent.
- **FR-013**: The system MUST refuse a commit request when nothing is staged,
  without opening a review.
- **FR-014**: A review MUST have a configurable maximum wait; on expiry the
  review is withdrawn and cannot create a commit afterwards.
- **FR-015**: Concurrent commit requests MUST get separate reviews with outcomes
  reported to the right requester.
- **FR-016**: With the worktree setting "free", a commit MUST proceed without
  prompt or review only when all hold: the target is a linked worktree (not the
  main checkout), it lies in the location the agent uses for its own worktrees,
  it carries the agent's creation marker, and it is on the branch the agent
  created for it.
- **FR-017**: A commit whose target directory or repository cannot be
  determined with confidence MUST be treated as a main-checkout commit.
- **FR-018**: The existing refusal of commits that also stage files, or stage
  implicitly, MUST apply in every mode, including free worktree mode.
- **FR-019**: If the gate fails, crashes, or is cut off before deciding, the
  commit MUST still require explicit user approval.
- **FR-020**: The agent's standing instructions MUST describe the new behaviour:
  that free worktree commits may be allowed, and that a commit reported as made
  or declined in the editor must not be retried.
- **FR-021**: The decision change MUST be recorded as an architecture decision
  amending the existing agent command-chain and sandbox decisions.

### Key Entities

- **Gate mode**: How commits on the user's checkouts are handled: prompt,
  editor review, or blocked. Has a declared default and optional overrides.
- **Worktree setting**: Whether commits in the agent's own worktrees bypass the
  gate: free or gated.
- **Override**: A user-set mode with a scope (session, repository, global),
  written only by the user.
- **Commit request**: One attempt by the agent to commit: target directory,
  proposed message, requester identity.
- **Review outcome**: Result of an editor review: committed (commit id,
  subject) or not committed (reason).
- **Agent worktree**: A linked worktree created by the agent, identified by
  location, creation marker, and its own branch.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In editor review mode, 100% of agent commit requests in the user's
  checkout either produce exactly one user-approved commit or none; zero
  duplicate or unapproved commits across a test run of at least 10 requests
  covering finish, cancel, timeout and editor-not-running.
- **SC-002**: The user can review the diff, edit the message and commit in one
  place, without switching to the terminal prompt, in under 30 seconds for a
  typical small commit.
- **SC-003**: Changing the mode from the editor takes effect on the very next
  commit request, with no rebuild and no session restart.
- **SC-004**: 0 of the agent's attempts to change the mode or overrides succeed.
- **SC-005**: With free worktree mode on, 100% of commits in the agent's own
  worktrees proceed without interruption, and 100% of commits in the main
  checkout, user-made worktrees, or user branches are still gated.
- **SC-006**: When the gate itself fails or is killed, 0 commits proceed without
  explicit approval.

## Assumptions

- The editor is Emacs with Magit, already running as a server for the user; the
  review uses Magit's normal commit buffer and keys.
- Commits made from the editor review are made by the user, with the user's
  own identity and signing key, not the agent's signing key. The user reviewed
  and approved them, so this is acceptable.
- The threat model is the cooperative agent of the sandbox policy decision: the
  worktree test guards against mistakes, not a hostile agent, since an agent in
  a worktree can write the shared repository metadata.
- The agent's worktree location, branch naming and creation marker follow the
  conventions observed in the installed agent version; if they change, the test
  fails safe to "gated".
- The declared default for checkouts is "prompt" until the editor review has
  been tried; the user may switch the default to "editor review" afterwards.
- Amend, fixup and other rewriting commit forms are out of scope for the review
  and keep the ordinary prompt.
- A newer agent version that can block the tool call when the gate fails is
  desirable; until then FR-019 relies on the existing static approval rule as
  fail-safe, which must be verified.
