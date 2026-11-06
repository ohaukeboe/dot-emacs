# Feature Specification: Project Tours and Project Audits

**Feature Branch**: `009-project-tour-audit`

**Created**: 2026-11-06

**Status**: Draft

**Input**: User description: "I really enjoy how the walkthrough skill works
with the emacs integration. Make two other skills which use the same emacs
integration. One is for getting to know a project. It should emphasize how
things work together, and how things are structured and use diagrams/code
excerpts where this is useful for getting to know the project. The other skill
is for discovering bugs and code smells in a project. The main difference
between this and the walkthrough skill I have now is that this is focused on
the entire project, and not just a diff."

Builds on feature `006-review-walkthrough`. Terms are those of `GLOSSARY.md`
(**Walkthrough**, **Step**, **Finding**, **Reply**, **Review comment**,
**Review hand-off**). This spec introduces two new terms, to be added to the
glossary:

- **Project tour**: an agent's guided introduction to a whole project at one
  commit, in reading order, explaining its structure and how its parts work
  together. It has steps, like a walkthrough, but shows code as it is rather
  than as a change.
- **Project audit**: an agent's review of a whole project at one commit for
  bugs and code smells, delivered as findings grouped into steps by area.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Get to know a project through a guided tour (Priority: P1)

The user opens a repository they do not know well, or one they have not
touched in months. They ask the agent for a project tour. The agent explores
the project and writes a tour as a series of steps in reading order: first the
big picture (what the project is for, its main parts and how they connect),
then each part in turn, then the paths that cross several parts (for example,
how a request, a build or a command flows through the system). Each step has
an explanation and, where it helps, a diagram and excerpts of the code it
talks about. When the agent finishes, the tour opens in the user's editor in
the same kind of view as a walkthrough.

**Why this priority**: This is the first of the two skills the user asked for,
and it delivers value on its own: it replaces reading a project file by file.

**Independent Test**: On a repository of at least 20 source files spread over
at least three directories, ask for a project tour. Confirm the tour opens by
itself, starts with an overview step, has steps that each cover one part or
one cross-cutting flow, and that at least one step shows a diagram and at
least one shows a code excerpt.

**Acceptance Scenarios**:

1. **Given** a repository, **When** the user asks for a project tour without
   arguments, **Then** the tour covers the whole project at the current
   commit.
2. **Given** the user names a directory or area, **When** the tour runs,
   **Then** it covers that area and explains how it connects to the rest of
   the project.
3. **Given** a tour is open, **Then** its first step is an overview that names
   the project's main parts and how they relate, before any step goes into a
   single part.
4. **Given** a step that explains how several parts interact, **Then** it
   includes a diagram showing those parts and the direction of the
   interaction.
5. **Given** a step that refers to specific code, **Then** it shows a short
   excerpt of that code, labelled with its file and lines, and visiting a line
   of the excerpt opens that file at that line.
6. **Given** the tour view is open, **When** the user moves to the next or
   previous step, **Then** point lands on that step's heading.

---

### User Story 2 - Audit a whole project for bugs and code smells (Priority: P1)

The user wants to know what is wrong with a project as it stands, not with a
recent change. They ask the agent for a project audit. The agent reviews the
whole project (or the area the user names) for defects and code smells. It
groups its findings into steps by area of the project, each step with a short
explanation of that area so the findings make sense in context. Each finding
shows its severity, title, explanation, failure scenario where there is one,
and the code it concerns. The audit opens in the user's editor in the same
kind of view as a walkthrough.

**Why this priority**: This is the second skill the user asked for, and it is
independent of the tour: either can be built and used without the other.

**Independent Test**: In a repository with one planted defect (for example an
off-by-one in a loop bound in a file not changed recently) and one planted
smell (for example two near-identical functions), run a project audit.
Confirm both appear as findings, each shown with an excerpt of the code it
concerns, and that moving to the next finding reaches each of them.

**Acceptance Scenarios**:

1. **Given** a repository with no uncommitted changes, **When** the user asks
   for an audit without arguments, **Then** the audit covers the whole
   project at the current commit.
2. **Given** the user names a directory or area, **When** the audit runs,
   **Then** only findings in that area are reported.
3. **Given** a finding that concerns specific lines, **When** the audit opens,
   **Then** the finding is shown with an excerpt of those lines and a way to
   visit them.
4. **Given** a finding that concerns no single place (for example, a missing
   test suite), **Then** it is shown at the top of the step it concerns most.
5. **Given** findings of different kinds, **Then** each finding says whether it
   is a defect (something that behaves wrongly) or a smell (something that
   works but is costly to keep), and its severity.
6. **Given** the audit found nothing, **When** it opens, **Then** the view says
   so and names what was covered.

---

### User Story 3 - Mark audit findings and hand off the accepted ones (Priority: P1)

Reading the audit, the user accepts the findings they want fixed, dismisses
others, and replies to some. They then use the review hand-off they already
use for walkthroughs. One prompt reaches the agent with the accepted findings,
their replies, and any pending review comments.

**Why this priority**: An audit is only useful if its findings can be acted on.
The user already relies on this loop for walkthroughs, and the audit must not
need a different one.

**Independent Test**: In an audit with three findings, accept one, dismiss
one, reply to one. Hand off. Confirm the prompt contains exactly the accepted
and replied findings, each with its file, lines and code excerpt, and that the
dismissed one is absent.

**Acceptance Scenarios**:

1. **Given** a finding at point in an audit, **When** the user accepts,
   dismisses, unmarks or replies to it, **Then** it behaves exactly as a
   walkthrough finding does, with the same keys.
2. **Given** accepted findings in both an audit and a walkthrough of the same
   repository, **When** the user hands off, **Then** one prompt contains both.
3. **Given** marked findings, **When** the user restarts the editor and
   reopens the audit, **Then** the marks are still there.

---

### User Story 4 - Comment on a tour or audit (Priority: P2)

While reading a tour or an audit, the user selects part of an explanation, a
diagram or a code excerpt and writes a review comment, as they do in a
walkthrough: often a question ("why does this go through the cache?"). The
comment is sent with the next hand-off, or at once as a direct comment.

**Why this priority**: The user named the editor integration as what they
enjoy about the walkthrough. Asking follow-up questions in place is what makes
a tour more than a document. It is P2 because the tour and audit are already
useful without it.

**Independent Test**: In a tour, select two lines of a code excerpt and send a
direct comment asking a question. Confirm the agent receives the question
together with the file, the lines and the step it was asked in.

**Acceptance Scenarios**:

1. **Given** a code excerpt, **When** the user comments on lines of it,
   **Then** the comment records the file and lines of the code it refers to,
   not positions within the view.
2. **Given** a passage of a step's explanation or a diagram, **When** the user
   comments on it, **Then** the comment quotes that passage and names the
   step.

---

### User Story 5 - Start and reopen tours and audits from the editor (Priority: P3)

From the review menu, the user asks the repository's agent session for a tour
or an audit, and later reopens the latest one, as they do for walkthroughs.

**Why this priority**: A convenience. Asking the agent directly already works
once Stories 1 and 2 do.

**Independent Test**: From the review menu, start an audit. Confirm the agent
session receives the request and the view opens when it finishes. Close it and
reopen it from the menu.

**Acceptance Scenarios**:

1. **Given** a repository with one agent session, **When** the user starts a
   tour or an audit from the menu, **Then** that session receives the request.
2. **Given** no tour (or audit) exists for the repository, **When** the user
   asks to reopen one, **Then** they are told none exists and offered to start
   one.
3. **Given** a tour or audit is re-run for the same repository and area,
   **Then** the new one replaces the old one.

### Edge Cases

- The project has moved on since the tour or audit was made: the view still
  shows code as it was at the recorded commit, and its header says that the
  current commit differs.
- The recorded commit no longer exists: reopening says so and suggests a
  re-run, instead of showing a partial view.
- The working tree has uncommitted changes: the tour or audit covers the
  committed state only, and the agent tells the user what it left out.
- The project is too large to cover in one run: the agent covers the most
  central parts first, and the overview (tour) or the report (audit) names
  the areas it did not cover, so the user can run again on one of them.
- A code excerpt or finding names lines that do not exist at the recorded
  commit: the tour or audit is rejected with the offending reference named,
  and no earlier tour or audit is replaced.
- Generated, vendored or lock files: they are not toured or audited line by
  line, though the tour may mention what they are for.
- A diagram is wider than the view: it stays readable without wrapping, for
  example by scrolling sideways, rather than being reflowed into nonsense.
- The audit would report the same smell in many places: it reports it once,
  with the places listed, rather than once per place.

## Requirements *(mandatory)*

### Functional Requirements

**Shared by tours and audits**

- **FR-001**: The agent MUST produce a project tour or a project audit on
  request, covering the committed state of the project at the current commit,
  or of one named area of it.
- **FR-002**: The agent MUST tell the user which uncommitted changes it left
  out, when there are any.
- **FR-003**: A tour or audit MUST record the commit it describes, a title, its
  steps in order, and the area it covers. Its code excerpts MUST be references
  to files and lines at that commit, not copies that could drift from it.
- **FR-004**: Each step MUST have a title and an explanation, and MAY have
  diagrams, code excerpts and findings.
- **FR-005**: Every code excerpt and finding anchor MUST name lines that exist
  in its file at the recorded commit. A tour or audit that breaks this MUST be
  rejected with the offending references named, and MUST NOT replace an
  existing one.
- **FR-006**: The view MUST open in the editor by itself when the agent
  finishes, and MUST show each step's title, explanation, diagrams, code
  excerpts and findings, with code shown with the language's highlighting.
- **FR-007**: Visiting a line of a code excerpt MUST open that file at that
  line.
- **FR-008**: The user MUST be able to move to the next and previous step and
  to the next and previous finding, with the same keys as in a walkthrough.
- **FR-009**: The user MUST be able to make review comments and direct
  comments on code excerpts, explanations and diagrams. A comment on an
  excerpt MUST name the file and lines of the code, not view positions.
- **FR-010**: Diagrams MUST be readable in the editor view as they are, without
  an external viewer.
- **FR-011**: Tours and audits MUST be kept per repository, outside the tracked
  files. A re-run for the same repository and area MUST replace the earlier
  one.
- **FR-012**: When the repository's current commit differs from the recorded
  one, the view MUST say so. When the recorded commit no longer exists,
  reopening MUST say so and suggest a re-run.
- **FR-013**: The user MUST be able to start, reopen and choose tours and audits
  from the review menu, as they do walkthroughs.
- **FR-014**: Neither skill MAY change code, stage, commit, push or post
  anything.

**Project tour**

- **FR-020**: A tour's first step MUST be an overview: the project's purpose,
  its main parts, and how they relate, with a diagram of those parts.
- **FR-021**: Steps MUST be ordered for understanding: overview first, then
  foundations before the parts that build on them, then flows that cross
  several parts.
- **FR-022**: Each step MUST explain how the part it covers connects to the
  others (what it uses, what uses it), not only what it contains.
- **FR-023**: A tour MUST include a diagram where a step explains structure or
  interaction between three or more parts, and a code excerpt where a step's
  point depends on specific code. It MUST NOT include excerpts that add
  nothing to the explanation.
- **FR-024**: Code excerpts MUST be short enough to read without scrolling the
  view, as a guide about 40 lines, and point to the full file for the rest.
- **FR-025**: A tour carries no findings. A tour MUST NOT be a disguised
  audit.

**Project audit**

- **FR-030**: An audit MUST look for both defects (code that behaves wrongly in
  some reachable situation) and smells (duplication, dead code, needless
  complexity, missing error handling at boundaries, untested risky code, and
  similar).
- **FR-031**: Each finding MUST carry a severity (high, medium, low), a kind
  (defect or smell), a title, an explanation, a failure scenario for defects,
  and an anchor to file and lines where it has one.
- **FR-032**: Findings MUST be grouped into steps by area of the project. Each
  step's explanation MUST give enough context about the area that its
  findings can be judged without reading other steps.
- **FR-033**: Audit findings MUST support everything walkthrough findings do:
  accept, dismiss, unmark, reply, and inclusion in the review hand-off, with
  their states persisting across editor restarts.
- **FR-034**: Each finding MUST be shown with an excerpt of the code it is
  anchored to, so the user can judge it without leaving the view.
- **FR-035**: The audit MUST state what it covered and what it skipped, so a
  clean audit is distinguishable from a shallow one.
- **FR-036**: The agent MUST check each defect finding against the code before
  reporting it, and mark findings it could not confirm as plausible rather
  than confirmed, as the built-in review does.

### Key Entities *(include if feature involves data)*

- **Project tour**: a guided introduction to a project at one commit. Holds a
  title, the commit, the area covered, and steps in order. At most one per
  repository and area.
- **Project audit**: a review of a project at one commit. Holds a title, the
  commit, the area covered, what was skipped, and steps holding findings. At
  most one per repository and area.
- **Step** (extended): as in a walkthrough, one concept with a title and an
  explanation. In a tour or audit it holds diagrams and code excerpts instead
  of diffs.
- **Code excerpt**: a reference to lines of one file at the recorded commit,
  shown as highlighted code with its file and line numbers.
- **Diagram**: a picture drawn as text inside a step, showing parts and how
  they relate.
- **Finding** (extended): as in a walkthrough, with a kind (defect or smell)
  added. Its state (unmarked, accepted, dismissed, sent) and reply behave the
  same.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After reading a tour of an unfamiliar project of up to 200 source
  files, the user can name its main parts and trace one end-to-end flow
  through them, without opening any file outside the tour.
- **SC-002**: For a project of up to 200 source files, the view opens within 5
  seconds of the agent finishing.
- **SC-003**: Every tour has an overview step with a diagram, and at least half
  of its other steps carry a diagram or a code excerpt.
- **SC-004**: In 100% of tours and audits accepted by the editor, every code
  excerpt and finding anchor names lines that exist at the recorded commit.
- **SC-005**: On a project with planted defects and smells, the audit reports
  at least 4 out of 5 of them, and fewer than 1 in 4 of its high-severity
  findings are false when checked by hand.
- **SC-006**: Every finding interaction available in a walkthrough (marking,
  replying, moving between findings, hand-off) works in an audit with the same
  keys.
- **SC-007**: Marks made on audit findings before an editor restart are all
  present after it.

## Assumptions

- Both skills are personal and reuse the existing walkthrough view, review
  comment loop, review hand-off and agent-session integration. They extend
  them; they do not replace them.
- "Same Emacs integration" means the same kind of buffer, keys, commenting and
  hand-off as the walkthrough, not a new viewer.
- Diagrams are drawn as plain text in the view. Rendered images are out of
  scope for this feature.
- The tour and audit describe committed code only. Touring or auditing
  uncommitted changes is out of scope; the existing walkthrough covers changes.
- The audit's findings come from the agent reviewing the code itself, using
  whatever whole-project review capability is available. It is not limited to
  the built-in diff review, which covers changes rather than whole projects.
- Security-focused scanning is out of scope; a dedicated security scan exists
  separately. The audit may still report an obvious security defect it meets.
- Accepted audit findings go to the agent as a prompt. Turning findings into
  tracked issues is out of scope and may be added later.
- A tour or audit is replaced on re-run; there is no history of earlier ones.
- The user does not edit, reorder or split steps in the view.
