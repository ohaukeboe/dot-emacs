# Feature Specification: Review Threads

**Feature Branch**: `016-review-threads`

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "The comments/direct messages used for communicating with claude from magit/walkthrough should optionally use separate threads in the claude session. This should be easilly toggleable from the contect menu under `@` like it is for other options in magit"

## Clarifications

### Session 2026-11-11

- Q: What is a "separate thread" for a review hand-off? → A: A forked Claude instance: a new Claude instance, in its own side window, that starts as a copy of the project's current conversation. It knows the context, but nothing said in it enters the main conversation.
- Q: Which hand-offs share a thread? → A: The user picks, as a second option in the `@` menu: either one thread per review item, reused for its follow-ups, or a new thread for every hand-off. Both are useful in different situations.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hand a review off into a thread (Priority: P1)

The user is working with a Claude instance on a branch and reviews its changes in Magit or a walkthrough. They want to ask about a hunk, or send a finding back, without that side discussion filling the main conversation. They turn on threads in the `@` menu and send the review as usual. A new Claude instance opens beside the main one, forked from the main conversation. It receives the review there, and the main conversation stays as it was.

**Why this priority**: This is the feature. Without it the toggle does nothing.

**Independent Test**: Turn threads on, write one review comment and send it with `@ s`. A second Claude instance opens with the prompt submitted, it knows what the main conversation was about, and the main conversation shows no new turn.

**Acceptance Scenarios**:

1. **Given** a project with one Claude instance and threads turned on, **When** the user sends pending review comments with `@ s`, **Then** a new Claude instance forked from that instance's conversation receives the review prompt and submits it, and the original instance receives nothing.
2. **Given** threads turned on, **When** the user sends a direct comment with `@ d` (including a reply to a finding), **Then** it goes to a thread rather than to the main conversation.
3. **Given** threads turned on, **When** the user pastes with `@ p` or `C-u @ d`, **Then** the prompt is pasted into the thread's input without being submitted, and the thread's window is selected.
4. **Given** threads turned off (the default), **When** the user hands off a review, **Then** it behaves exactly as today: the prompt goes to the project's Claude instance.
5. **Given** threads turned on, **When** a hand-off goes to a thread, **Then** its comments and findings are marked sent, as they are today.

---

### User Story 2 - Toggle threads from the `@` menu (Priority: P1)

The user switches threads on and off from the `@` menu, the way they toggle switches in other Magit menus, and sees the current state in the menu.

**Why this priority**: The request names this as the way to control the feature. Without it the feature cannot be reached.

**Independent Test**: Open `@`, toggle the threads option on, then off. The menu shows the state each time, and a hand-off follows it.

**Acceptance Scenarios**:

1. **Given** the `@` menu is open, **When** the user presses the threads option's key, **Then** it is shown as on, and the next hand-off from that menu goes to a thread.
2. **Given** the user turned threads on, **When** they open `@` again later in the same Emacs session, **Then** the option is still on.
3. **Given** the user wants threads on by default, **When** they save the menu's options the standard way Magit menus are saved, **Then** threads start on in later Emacs sessions.

---

### User Story 3 - Choose how hand-offs are grouped into threads (Priority: P2)

Sometimes the user wants a long-running discussion per comment or finding, where each follow-up goes back to the same thread. Other times they want every hand-off to start fresh. A second option in the `@` menu picks between **per item** (one thread per review item, reused for its follow-ups) and **per hand-off** (a new thread every time).

**Why this priority**: The basic thread flow works with either grouping. This option makes the feature fit both ways of working.

**Independent Test**: With per item selected, reply to a finding already sent in a thread. The reply goes to that same thread. Switch to per hand-off and send it again: a new thread opens.

**Acceptance Scenarios**:

1. **Given** per-item grouping and a finding already handed off in a thread, **When** the user replies to it and sends it (a follow-up), **Then** it goes to that same thread, and no new instance is started.
2. **Given** per-item grouping and a direct comment already sent in a thread, **When** the user sends another direct comment on the same target (the same hunk lines, file, commits, step or passage), **Then** it goes to that same thread.
3. **Given** per-item grouping and a `@ s` hand-off with several items that have never been sent, **Then** they go together into one new thread, and that thread becomes the thread of each of them.
4. **Given** per-item grouping and a `@ s` hand-off with items from different existing threads plus new items, **Then** each existing thread receives its own items, and the new items go together into one new thread.
5. **Given** per-hand-off grouping, **When** the user hands anything off, **Then** a new thread is started, even for a follow-up.
6. **Given** per-item grouping and an item whose thread was closed, **When** it is handed off again, **Then** a new thread is forked and becomes that item's thread.

---

### Edge Cases

- No Claude instance runs for the project when threads are on: the hand-off is refused with the same kind of message as today, and nothing is marked sent. A thread needs a conversation to fork from.
- Several Claude instances run for the project: the main conversation to fork from is chosen the same way the hand-off target is chosen today (the only one, the only visible one, the most recent, or ask with a prefix argument). Thread instances are never offered as fork sources. From `@` the prefix argument means paste only, so the asking path is not reachable from the review menu.
- Threads are turned off after some items got threads: hand-offs go to the main instance again, and the remembered threads are kept for when threads are turned back on.
- The thread instance fails to start: the user sees an error, and nothing is marked sent.
- Emacs restarts: per-item thread links are lost. Comments are in memory anyway. A finding's follow-up then opens a new thread.
- Many threads pile up: each thread is a normal Claude instance and is closed the normal way. The feature does not close threads by itself.
- The walkthrough request (`@ W`) and the `magit_review_comments` tool are not hand-offs. Threads do not change them.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `@` menu MUST offer a toggle, off by default, that sends review hand-offs to a separate thread instead of the project's main Claude conversation.
- **FR-002**: The `@` menu MUST offer a choice of thread grouping, **per item** or **per hand-off**. It applies only while threads are on, and per item is the default.
- **FR-003**: Both options MUST be shown in the menu with their current value. They MUST keep their value for the rest of the Emacs session, and MUST be savable as defaults the same way other Magit menu options are.
- **FR-004**: A thread MUST be a new Claude instance for the same project, started as a fork of the main conversation. It has the main conversation's history up to the fork, and nothing said in it is added to the main conversation.
- **FR-005**: A thread MUST be shown in its own Claude side window and MUST be named so that the user can tell it is a review thread and what it is about.
- **FR-006**: Every hand-off command MUST honour the toggle: send (`@ s`), paste (`@ p`), and direct comment or finding reply (`@ d`, with or without prefix argument).
- **FR-007**: The prompt text handed to a thread MUST be the same as it would be without threads.
- **FR-008**: With per-item grouping, the system MUST remember which thread each handed-off review comment and finding went to. Follow-ups and new direct comments on the same target MUST go back to that thread while it is still open.
- **FR-009**: With per-item grouping, a hand-off of several items MUST send each group of items that share a live thread to that thread, and all items without one together to one new thread.
- **FR-010**: With per-hand-off grouping, every hand-off MUST start one new thread for all of its items.
- **FR-011**: Items MUST be marked sent only after their prompt reached its thread. If no thread can be started, nothing is marked sent.
- **FR-012**: With threads off, behaviour MUST be unchanged from today.
- **FR-013**: The review package MUST stay agent-agnostic. Forking a conversation is the agent glue's job, which the config wires in, as the send function is today.

### Key Entities

- **Thread**: A forked Claude instance that receives review hand-offs. It belongs to one project and was forked from one main conversation. It is a Claude instance in every other respect.
- **Thread link**: The record that a review comment or finding was last handed off in a given thread. Used only by per-item grouping, and kept in memory for the Emacs session.
- **Thread options**: The on/off toggle and the grouping choice, as menu options of `@`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With threads on, a full review hand-off adds 0 turns to the main conversation.
- **SC-002**: Turning threads on or off takes one key press in the `@` menu, and the menu shows the current state without opening anything else.
- **SC-003**: With per-item grouping, 100% of follow-ups on an item whose thread is still open land in that thread.
- **SC-004**: A thread can answer a question about the earlier main conversation, such as what the branch is for, without the user restating it.
- **SC-005**: With threads off, every existing review hand-off test passes unchanged.

## Assumptions

- "Separate thread in the Claude session" means a forked Claude instance (clarified), not a subagent inside the main instance and not a fresh, empty instance.
- Claude Code can start a new session as a fork of an existing one. The glue can find the main instance's conversation to fork.
- Thread links live in memory only, like pending review comments. Persisting them across Emacs restarts is out of scope.
- A thread is never itself used as the source of a new fork. Forks always start from the main conversation chosen as today.
- Closing threads, listing threads and merging a thread's outcome back into the main conversation are out of scope. The user does that by hand.
- The beads transient (`#`) and other users of the shared paste helper are otherwise not affected. Like hand-offs with threads off, their sends now skip thread instances when the main instance is picked (intended, research R7).
