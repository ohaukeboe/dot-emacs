# Feature Specification: Review Walkthroughs

**Feature Branch**: `006-review-walkthrough`

**Created**: 2026-10-23

**Status**: Draft

**Input**: User description: Beads issue `dot-emacs-6ni` (Review walkthroughs in
Magit) and its children `dot-emacs-6ni.1`–`.6`. Originating request: "I really
like how trailofbits' review-walkthrough lets me walk through the code changes.
I also like the quality from Claude's code-review. But I want to be able to
check this in an Emacs buffer similar to Magit so that I can easily highlight
lines and add comments using my custom claude-magit integration, and get the
same code navigation features that Magit gives. I'd also like then to have an
easy way to mark the review suggestions that I want to solve." Terms are those
of `GLOSSARY.md` (**Walkthrough**, **Step**, **Finding**, **Review comment**,
**Review hand-off**); the storage decision is
`docs/adr/0007-walkthrough-diffs-from-shas.md`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read a branch's changes as a guided walkthrough (Priority: P1)

The user has a branch with several commits, usually written by an agent, and
wants to understand it before deciding what to change. They ask the agent for a
walkthrough. The agent reviews the committed changes between the branch's base
and its head, splits them into steps in reading order, and writes one
explanation per step. When it finishes, a walkthrough view opens in the user's
editor. It shows each step's heading and explanation, followed by the diffs that
belong to that step, in the order the agent chose. The diffs behave like any
other diff the user reviews in the editor: they fold, and visiting a line opens
the file at that line.

**Why this priority**: This is the core of the request. Without the guided,
navigable view nothing else in the feature has a place to live, and on its own
it already replaces reading a large diff in file order.

**Independent Test**: On a branch with at least three commits touching at least
four files, ask for a walkthrough. Confirm the view opens by itself, the steps
appear in the agent's order with their explanations, every changed hunk appears
in exactly one step, and visiting a changed line opens that file at that line.

**Acceptance Scenarios**:

1. **Given** a branch whose commits are ahead of the default branch, **When**
   the user asks for a walkthrough without naming a base, **Then** the base is
   the merge-base with the remote's default branch, and only committed changes
   are covered.
2. **Given** the user names a base reference, **When** the walkthrough runs,
   **Then** it covers the changes between that reference and the head.
3. **Given** the branch also has uncommitted changes, **When** the walkthrough
   runs, **Then** they are left out and the agent says that it left them out.
4. **Given** one file contains two unrelated changes, **When** the agent builds
   the steps, **Then** it may place the two changes in different steps, and
   each change still appears exactly once.
5. **Given** the walkthrough view is open, **When** the user moves to the
   next or previous step, **Then** point lands on that step's heading.

---

### User Story 2 - See the agent's findings in place (Priority: P1)

As part of the same run, the agent reviews the changes for defects using the
built-in review, which reports findings with a severity, a title, an
explanation and usually a failure scenario. Each finding appears in the
walkthrough under the lines it concerns, within the step that owns those lines.
A finding that names no lines appears at the top of its step.

**Why this priority**: The user asked for the quality of the built-in review in
this view. Findings shown next to the lines they concern are what make the
walkthrough worth more than the review's plain list.

**Independent Test**: On a branch with a planted defect (for example an
off-by-one in a loop bound), run a walkthrough. Confirm a finding for it
appears directly below the affected line, with its severity and failure
scenario, and that moving to the next finding reaches it.

**Acceptance Scenarios**:

1. **Given** the review reports a finding anchored to lines of a changed file,
   **When** the walkthrough opens, **Then** the finding is shown below the last
   anchored line, inside the step that owns that hunk.
2. **Given** a finding without an anchor, **When** the walkthrough opens,
   **Then** it is shown below the explanation of the step the agent assigned it
   to.
3. **Given** the review reports no findings, **When** the walkthrough opens,
   **Then** the view says that there are no findings instead of showing an
   empty list.
4. **Given** several findings, **When** the user moves to the next or previous
   finding, **Then** point moves between findings across step boundaries.

---

### User Story 3 - Mark findings and hand the accepted ones off (Priority: P2)

Reading through, the user decides which findings they want fixed. They accept
some, dismiss others and leave the rest unmarked. Then they use the review
hand-off they already use for review comments. One prompt goes to the agent
with the accepted findings and any pending review comments, and all of them are
marked sent. Dismissed findings are not mentioned.

**Why this priority**: This closes the loop the user asked for ("an easy way to
mark the review suggestions that I want to solve"). It depends on the view and
the findings existing first.

**Independent Test**: In a walkthrough with three findings, accept one, dismiss
one, and leave one unmarked. Add one review comment on a hunk. Hand off. Confirm
the agent's prompt contains exactly the accepted finding and the review comment,
both now show as sent, and the dismissed and unmarked findings are absent from
the prompt.

**Acceptance Scenarios**:

1. **Given** a finding at point, **When** the user accepts, dismisses or
   unmarks it, **Then** its state is shown on the finding at once.
2. **Given** marked findings, **When** the user closes the view and restarts
   the editor, **Then** reopening the walkthrough shows the same marks.
3. **Given** accepted findings and no pending review comments, **When** the
   user hands off, **Then** the prompt contains the accepted findings alone.
4. **Given** each accepted finding sent in a hand-off, **Then** the prompt
   names its file and lines, severity, title, explanation and the diff it is
   anchored to, in the same shape as a review comment.
5. **Given** a finding already sent, **When** the user hands off again,
   **Then** it is not sent a second time.
6. **Given** nothing is accepted and no review comment is pending, **When** the
   user hands off, **Then** nothing is sent and the user is told why.

---

### User Story 4 - Comment on the walkthrough's lines (Priority: P2)

While reading a step, the user selects lines in one of its diffs and writes a
review comment, exactly as they do in any other diff view. The comment is drawn
under those lines, counted on the file heading, and sent with the next
hand-off. A direct comment sends it at once on its own.

**Why this priority**: The user named the existing comment integration as the
reason for wanting the walkthrough in the editor. It is P2 because it reuses an
existing capability, which only has to keep working in the new view.

**Independent Test**: In a walkthrough, select two changed lines and add a
review comment. Confirm it is drawn below them and listed among the pending
review comments, and that the hand-off sends it with the file, lines and diff.

**Acceptance Scenarios**:

1. **Given** a hunk or a region of a hunk in the walkthrough, **When** the user
   adds a review comment, **Then** it records the file, the old and new line
   ranges and the diff it refers to, the same way as in any other diff view.
2. **Given** a review comment made in the walkthrough, **When** the user opens
   an ordinary diff of the same range, **Then** the comment is drawn there as
   well, and the other way round.

---

### User Story 5 - Start and reopen walkthroughs from the editor (Priority: P3)

From the review menu in their editor, the user asks the agent session of the
repository to produce a walkthrough of the current branch, without typing the
request in the agent's terminal. Later, the same menu reopens the current
branch's walkthrough, or with a prefix lets them choose another branch's
walkthrough.

**Why this priority**: A convenience. Asking the agent directly already works
once Story 1 does.

**Independent Test**: From the review menu, start a walkthrough. Confirm the
agent session receives the request and the view opens when it finishes. Close
the view and reopen it from the menu.

**Acceptance Scenarios**:

1. **Given** a repository with one agent session, **When** the user starts a
   walkthrough from the menu, **Then** that session receives the request for
   the current branch.
2. **Given** a repository with no walkthrough for the current branch, **When**
   the user asks to reopen it, **Then** they are told none exists and offered
   to start one.
3. **Given** a walkthrough is re-run on the same branch, **Then** the new one
   replaces the old one, and findings from the old one are not carried over.

### Edge Cases

- The branch was rebased after the walkthrough and its old commits were
  garbage-collected: reopening says the walkthrough's commits are gone and
  suggests re-running it, instead of showing a partial view.
- The branch moved on after the walkthrough (the user committed fixes): the
  view keeps showing the changes as they were reviewed, and its header states
  that the branch head has moved since.
- The agent's step list leaves a changed hunk out, or lists it twice: the run
  fails with the hunk named, and no walkthrough file replaces the previous one.
- A finding is anchored to lines no step shows: it is shown at the top of the
  step that owns its file, marked as not placed, rather than dropped.
- The user widens the diff context so that two hunks merge across steps: the
  merged hunk appears in each step that owns part of it. Nothing is hidden.
- The diff contains binary files or renames without content changes: they
  belong to a step like any other file, shown as the diff view shows them.
- Two editors or the agent write marks to the same walkthrough at once: the
  last write wins for that finding, and no other finding's state is lost.
- The review reports a field the walkthrough does not know (for example, a new
  verdict value): the finding is still shown, with the unknown value as text.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The agent MUST produce a walkthrough on request, covering only
  committed changes between a base and a head commit. The base is the
  merge-base with the remote's default branch unless the user names one.
- **FR-002**: The agent MUST tell the user which uncommitted changes it left
  out, when there are any.
- **FR-003**: A walkthrough MUST record its base and head commits, its title,
  its steps in order and its findings. It MUST NOT depend on a copy of the
  diff (ADR 0007).
- **FR-004**: Each step MUST have a title and an explanation, and MUST own
  either whole files or, where one file holds unrelated changes, named line
  ranges of the new version of a file.
- **FR-005**: Every hunk of the base-to-head diff, at the default context, MUST
  belong to exactly one step. A walkthrough that breaks this MUST be rejected
  with the offending hunks named, and MUST NOT replace an existing one.
- **FR-006**: Steps MUST be ordered for understanding: definitions before their
  consumers, wiring after the parts it connects, tests beside or after their
  subjects.
- **FR-007**: The agent MUST obtain its findings from the built-in review run on
  the same range, and keep each finding's severity, title, explanation, failure
  scenario, verdict (when given) and line anchor (when given).
- **FR-008**: The walkthrough view MUST open in the editor by itself when the
  agent finishes, and MUST show for each step its title, explanation, findings
  and diffs.
- **FR-009**: Diffs in the view MUST support the user's existing diff
  interactions: folding, visiting the file at a line, review comments and direct
  comments, with their decorations.
- **FR-010**: Findings MUST be drawn below the last line they are anchored to,
  inside the step that shows that line, with severity and title visible without
  expanding them.
- **FR-011**: The user MUST be able to move to the next and previous step, and
  to the next and previous finding.
- **FR-012**: The user MUST be able to accept, dismiss or unmark the finding at
  point. Its state MUST be visible on the finding.
- **FR-013**: Finding states MUST persist with the walkthrough and survive
  closing the view and restarting the editor.
- **FR-014**: The review hand-off MUST send the accepted, unsent findings
  together with the pending review comments in one prompt, and mark all of them
  sent. It MUST NOT mention dismissed or unmarked findings.
- **FR-015**: The agent MUST be able to read the user's accepted findings
  through the same channel it already uses to re-read review comments.
- **FR-016**: Walkthroughs MUST be kept per repository and per branch, outside
  the tracked files. A re-run on the same branch MUST replace the earlier one.
- **FR-017**: The user MUST be able to reopen the current branch's walkthrough
  and choose another branch's walkthrough from the review menu.
- **FR-018**: The user MUST be able to ask the repository's agent session for a
  walkthrough of the current branch from the review menu.
- **FR-019**: When the head commit of the branch differs from the
  walkthrough's head, the view MUST say so. When the walkthrough's commits no
  longer exist, reopening MUST say so and suggest a re-run.
- **FR-020**: Explanations and finding bodies MUST be shown as formatted text
  (code spans, lists and paragraphs), not as raw markup.

### Key Entities *(include if feature involves data)*

- **Walkthrough**: an agent's guided tour of one branch's committed changes.
  It holds a title, its base and head commits, its steps in order, and the
  branch and repository it belongs to. At most one per branch.
- **Step**: one concept of a walkthrough. It holds a title, an explanation and
  what it owns: whole files, or line ranges of a file. It holds the findings
  assigned to it.
- **Finding**: a suggestion from the agent. It holds a severity (high, medium,
  low), a title, an explanation, optionally a failure scenario and a verdict,
  optionally an anchor (file, side, first and last line), and a state
  (unmarked, accepted, dismissed, sent).
- **Review comment** (existing): the user's own remark on a hunk, a region or a
  file. Sent through the same hand-off as accepted findings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a branch of up to 30 changed files, the view opens within 5
  seconds of the agent finishing, and each step's diffs appear without a
  further request.
- **SC-002**: In 100% of walkthroughs accepted by the editor, every changed hunk
  appears in exactly one step.
- **SC-003**: Marking a finding takes one keystroke, and moving between any two
  adjacent findings takes one keystroke.
- **SC-004**: Handing off N accepted findings and M review comments takes one
  command and produces one prompt with exactly N + M items.
- **SC-005**: Every interaction the user has on an ordinary diff (folding,
  visiting, commenting, direct comments) works in the walkthrough view with the
  same keys.
- **SC-006**: Marks made before an editor restart are all present after it.

## Assumptions

- The user works in one repository at a time, with the existing agent session
  integration and review comment loop already in place. This feature extends
  them; it does not replace them.
- The built-in review keeps reporting severity, title, explanation, failure
  scenario and an optional line anchor. Its exact field names are not
  documented, so the agent maps fields by meaning, and a finding with an
  unknown field still appears.
- Walkthroughs are personal: they are not shared, published or posted to a
  code host. Submitting a review to a pull request is out of scope.
- Reviewing uncommitted changes, single commits and pull requests by number is
  out of scope; the range is always base to head of the current branch.
- Accepted findings go to the agent as a prompt. Turning findings into tracked
  issues is out of scope and may be added later.
- A walkthrough is replaced on re-run; there is no history of earlier
  walkthroughs for a branch.
- Steps are written by the agent; the user does not edit, reorder or split
  steps in the view.
