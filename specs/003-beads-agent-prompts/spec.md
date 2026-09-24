# Feature Specification: Prompt the Coding Agent from a Beads Issue

**Feature Branch**: `main`

**Created**: 2026-09-24

**Status**: Draft

**Input**: User description: "The beads emacs package should also support prompting the agent directly. It should have a quick prompt feature where it just assigns the issue id to the prompt, and lets the user type. It should also have a defined prompt which makes the agent explore the issue and ask any questions for decisons that need to be made. This last one should not implement it, as the user should be able to chose freely what skills if any to use for the implementation"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start a prompt about an issue and finish it by hand (Priority: P1)

A developer looking at an issue in the beads section wants to tell the project's
coding agent something about it. They invoke the quick prompt on the issue. The
agent's input now holds a reference to the issue's identifier, the agent is in front
of them with the cursor after that reference, and nothing has been sent. They type
the rest of the instruction in their own words and send it when they are ready.

**Why this priority**: This is the smallest piece that connects the tracker to the
agent, and it is the one used most often: every instruction about an issue starts by
naming the issue. It removes copying the identifier by hand and switching to the
agent's window, and it leaves the wording, and the choice of skill, entirely to the
developer.

**Independent Test**: With an agent session running for the repository, put point on
an issue, invoke the quick prompt, and confirm that the agent's input contains the
issue identifier, the agent has focus, nothing has been submitted, and anything typed
next is appended to that input.

**Acceptance Scenarios**:

1. **Given** point is on an issue and the repository has one agent session, **When**
   the developer invokes the quick prompt, **Then** that session's input holds a
   reference to the issue's identifier, the session is shown and focused, and the
   input is not submitted.
2. **Given** the quick prompt has been placed, **When** the developer types and sends,
   **Then** the agent receives the identifier followed by exactly what the developer
   typed.
3. **Given** the region covers several issues, **When** the developer invokes the
   quick prompt, **Then** the input references every issue in the region, in the
   order they are listed.
4. **Given** the developer is viewing an issue's full detail view, **When** they
   invoke the quick prompt, **Then** it references the issue that view shows.
5. **Given** the agent's input already holds text the developer had not sent,
   **When** the quick prompt is invoked, **Then** that text is kept and the reference
   is added to it rather than replacing it.

---

### User Story 2 - Have the agent study an issue and ask what must be decided (Priority: P1)

A developer is about to take on an issue whose description leaves open choices. They
invoke "explore" on the issue. The agent receives a fixed, prepared instruction and
starts at once: it reads the issue with its relations and comments, explores the parts
of the repository the issue concerns, and then comes back with a summary of its
understanding and the questions whose answers would change the implementation. It
stops there. It writes no code, changes no file and no tracker state, and does not
start an implementation workflow. The developer answers the questions and then
decides how, and with which skills if any, the work is carried out.

**Why this priority**: This is the second half of the request, and the one that saves
the most time: the agent's exploration runs while the developer does something else,
and its questions surface decisions before any code exists. It is independent of
Story 1 — either one alone is useful.

**Independent Test**: Invoke explore on an issue whose description is ambiguous, let
the agent run to completion, and confirm that it answered with a summary and a list of
decision questions, that the working tree and the tracker are unchanged, and that the
agent is waiting for the developer rather than continuing.

**Acceptance Scenarios**:

1. **Given** point is on an issue, **When** the developer invokes explore, **Then**
   the agent receives the prepared instruction naming that issue, and the instruction
   is submitted without further input.
2. **Given** the agent has received the explore instruction, **When** it finishes,
   **Then** its reply contains its understanding of the issue and the open decisions,
   each phrased as a question, with the options it sees where there are any.
3. **Given** the agent has received the explore instruction, **When** it finishes,
   **Then** no file in the repository has been changed, no issue has been claimed,
   closed, commented on or edited, and no implementation skill or workflow has been
   started.
4. **Given** the issue leaves no decision open, **When** the agent finishes, **Then**
   it says so explicitly instead of inventing questions.
5. **Given** the developer has changed the prepared instruction's wording in their
   configuration, **When** they invoke explore, **Then** their wording is sent, with
   the issue's identifier filled in.
6. **Given** explore has been sent, **When** the agent is not visible, **Then** the
   developer is told the instruction was sent and to which session, and their current
   window is left as it was.

---

### User Story 3 - Find both prompts in the issue menu (Priority: P2)

The two prompt commands appear in the same per-issue menu that already offers claim,
close, comment, assign, priority and relations, under their own heading, so a
developer who knows the menu finds them without documentation.

**Why this priority**: Discoverability only. Both commands work without it.

**Independent Test**: Open the issue menu on an issue and confirm both entries are
present, labelled with what they do, and marked unavailable when the repository has no
agent session.

**Acceptance Scenarios**:

1. **Given** point is on an issue, **When** the issue menu is opened, **Then** it
   offers a quick prompt entry and an explore entry under an agent heading.
2. **Given** the repository has no agent session running, **When** the issue menu is
   opened, **Then** both entries are shown as unavailable rather than failing when
   chosen.

---

### Edge Cases

- **No agent session for the repository**: both commands say so plainly and change
  nothing — no prompt text is lost, no window changes, no session is started behind
  the developer's back.
- **Several agent sessions for the repository**: the developer chooses which one
  receives the prompt, the same way the existing review hand-off already asks.
- **No issue at point**: both commands say there is no issue here and do nothing.
- **Region covers several issues when explore is invoked**: explore works on a single
  issue; it tells the developer so and does nothing, rather than silently picking one.
- **Issue closed since the listing was drawn**: both commands still send the
  identifier; the agent reads the issue's current state itself. The prompt is not
  refused, since exploring a closed issue can be deliberate.
- **Agent is busy with an earlier request**: the text is delivered the same way it
  would be typed; queuing or rejecting it is the agent's own behaviour, not this
  feature's.
- **Prepared instruction customised without an identifier placeholder**: the issue's
  identifier is still delivered, so the agent is never asked to explore an unnamed
  issue.
- **Repository without a tracker**: nothing changes; no command or menu entry appears.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Users MUST be able to place a reference to the issue at point into the
  input of the repository's agent session with a single command, without submitting
  it.
- **FR-002**: After the quick prompt, the agent session MUST be shown and focused with
  the cursor at the end of the input, so the next keystrokes continue the prompt.
- **FR-003**: The quick prompt MUST add to any unsent text already in the agent's
  input rather than replace it.
- **FR-004**: When the region covers several issues, the quick prompt MUST reference
  all of them, in the order they are listed.
- **FR-005**: Users MUST be able to send a prepared "explore" instruction about the
  issue at point to the agent with a single command, and the instruction MUST be
  submitted without further input.
- **FR-006**: The explore instruction MUST ask the agent to read the issue together
  with its relations and comments, and to explore the parts of the repository it
  concerns, before answering.
- **FR-007**: The explore instruction MUST ask the agent to reply with its
  understanding of the issue and with every decision that has to be made before
  implementation, each as a question, with the options it sees; and to say so
  explicitly when nothing needs deciding.
- **FR-008**: The explore instruction MUST forbid the agent from implementing the
  issue: no file changes, no tracker changes (claim, close, comment, edit), no
  commits, and no starting of an implementation skill or workflow. It MUST tell the
  agent to stop and wait for the developer after asking its questions.
- **FR-009**: The wording of the explore instruction MUST be changeable in the user's
  configuration, with a placeholder for the issue identifier.
- **FR-010**: The issue identifier MUST always reach the agent, even when a customised
  explore instruction lacks the placeholder.
- **FR-011**: Both commands MUST work on the issue shown by an issue's full detail
  view when invoked from one.
- **FR-012**: Both commands MUST appear in the existing per-issue menu under their own
  heading, and MUST be shown as unavailable when the repository has no agent session.
- **FR-013**: When there is no agent session, no issue at point, or (for explore) more
  than one issue selected, the command MUST say so plainly and leave the agent's
  input, the buffers and the window configuration unchanged.
- **FR-014**: When several agent sessions belong to the repository, the developer MUST
  be able to choose which one receives the prompt.
- **FR-015**: Neither command may start an agent session, change the tracker, or
  change the working tree itself.
- **FR-016**: After explore is sent, the developer's current window MUST stay where it
  was, and a message MUST confirm which session received it.

### Key Entities

- **Issue**: the unit of work the tracker holds, identified by its identifier. The
  prompts carry only the identifier; the agent reads the rest from the tracker.
- **Agent session**: the coding-agent session running for this repository, with an
  input the developer types into. There can be none, one or several.
- **Quick prompt**: an unsent input consisting of a reference to one or more issues,
  completed by the developer.
- **Explore instruction**: the prepared, configurable text that asks the agent to
  study one issue and ask its decision questions without implementing anything.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From an issue in the status buffer, the developer is typing the rest of
  an instruction to the agent within two keystrokes, and never types or pastes an
  identifier.
- **SC-002**: Sending the explore instruction takes at most two keystrokes and no
  further input.
- **SC-003**: In 10 explore runs on real issues of this repository, 10 end with a
  summary and a list of questions (or an explicit "nothing to decide"), and 0 leave a
  changed file, a changed issue or a started implementation behind.
- **SC-004**: Every failure case — no session, no issue at point, several issues for
  explore — produces a message naming the problem, and in 100% of them the agent's
  input and the window layout are unchanged.
- **SC-005**: A developer who knows the issue menu finds both commands without
  documentation on first attempt.

## Assumptions

- "The agent" is the coding-agent session already integrated with Emacs for this
  repository — the same one the existing review hand-off sends comments to. No new
  agent integration is introduced, and the same session choice applies.
- The quick prompt is typed in the agent's own input, not in a separate Emacs buffer;
  the developer's text therefore never passes through this feature.
- The prompts name the issue by identifier only. The agent reads description,
  relations and comments from the tracker itself, so the prompt cannot go stale and
  long descriptions are not pasted into the agent.
- Starting an agent session is out of scope: the developer starts one the usual way.
- The explore instruction is a request to the agent, not an enforced restriction.
  Whether the agent honours it is measured by SC-003, not guaranteed by a permission
  mechanism.
- What happens after the questions are answered — which skill, workflow or plain
  instruction carries out the work — is the developer's choice and out of scope.
- Explore works on one issue at a time; exploring several issues together is out of
  scope for this version.
