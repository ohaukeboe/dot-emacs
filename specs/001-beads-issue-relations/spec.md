# Feature Specification: Beads Issue Relations in Magit

**Feature Branch**: `magit-beads`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "The beads plugin for magit/emacs should also mark parent and blockers and make it easy to move to them"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See an issue's relations without leaving the status buffer (Priority: P1)

A developer looking at the beads section of the Magit status buffer sees, for every
listed issue, whether that issue belongs to a parent issue and whether anything is
holding it up. The marker is part of the issue's entry, so the information is there
before any command is invoked and before any other buffer is opened.

**Why this priority**: Marking is the prerequisite for everything else. Without a
visible relation there is nothing to navigate to, and an issue that silently depends
on another is the case the tracker exists to prevent. This story alone already
delivers value: it answers "why is this not moving?" at a glance.

**Independent Test**: Populate a tracker with one claimed issue that has a parent,
one claimed issue blocked by an open issue, one blocked by a closed issue, and one
with no relations at all. Open the Magit status buffer and confirm each issue's entry
states exactly its own relations and nothing more, and that the section lists the same
issues it listed before the feature.

**Acceptance Scenarios**:

1. **Given** an issue that has a parent issue, **When** the beads section is
   displayed, **Then** the issue's entry names the parent's identifier and title.
2. **Given** a claimed issue that is blocked by two open issues, **When** the beads
   section is displayed, **Then** the issue's entry reports both blockers, each with
   its identifier and current status.
3. **Given** an issue whose only dependency is already closed, **When** the beads
   section is displayed, **Then** the issue is not marked as blocked.
4. **Given** an issue with no parent and no dependencies, **When** the beads section
   is displayed, **Then** its entry looks exactly as it does today, with no empty
   relation line and no extra vertical space.
5. **Given** an issue that other issues depend on, **When** the beads section is
   displayed, **Then** the issue's entry reports how many issues point at it, so the
   developer knows the relation exists in that direction too.
6. **Given** a parent issue whose only inbound relations are its children, **When**
   the beads section is displayed, **Then** it carries no dependents mark — the
   tracker's listing does not count children — and the children remain reachable by
   navigating to them.

---

### User Story 2 - Move to a related issue in one step (Priority: P1)

From an issue in the beads section, the developer moves to the issue's parent, to one
of its blockers, or to one of the issues that depend on it, without typing an
identifier and without knowing whether the target happens to be listed in the current
buffer.

**Why this priority**: The stated request is that relations be easy to move to. A
marker that has to be copied by hand into a prompt is not navigation. This story is
independently testable and useful even if back-navigation (Story 3) is never built.

**Independent Test**: With point on a blocked issue, invoke the navigation command and
confirm the blocker becomes the current issue, both when the blocker is listed
elsewhere in the same buffer and when it is not listed at all.

**Acceptance Scenarios**:

1. **Given** point is on an issue with exactly one parent, **When** the developer
   invokes "go to parent", **Then** the parent issue becomes current without any
   prompt.
2. **Given** point is on an issue with several blockers, **When** the developer
   invokes "go to blocker", **Then** they are offered the blockers to choose from,
   each shown with its identifier, status and title, and the chosen one becomes
   current.
3. **Given** the related issue is itself listed in the current buffer, **When** the
   developer moves to it, **Then** point lands on that entry in place, with the entry
   expanded and visible, rather than opening a second view of the same issue.
4. **Given** the related issue is not listed in the current buffer (it is closed, or
   filtered out), **When** the developer moves to it, **Then** its full detail view
   opens.
5. **Given** point is on an issue with no relation of the requested kind, **When** the
   developer invokes the corresponding navigation command, **Then** they are told so
   plainly and nothing else changes — no prompt, no new buffer, no moved point.
6. **Given** the developer is viewing an issue's full detail view rather than the
   status buffer, **When** they invoke a navigation command, **Then** it acts on the
   issue that view shows.

---

### User Story 3 - Come back from where you jumped (Priority: P2)

Having followed a chain of blockers away from the issue they meant to work on, the
developer returns to the issue they started from.

**Why this priority**: Following a dependency chain is exploratory; without a way
back, each jump costs the developer their place, and they stop using the jumps. Still
secondary — a jump that cannot be undone is already better than no jump.

**Independent Test**: From an issue, follow two relations in a row, then invoke the
return command twice and confirm each invocation lands on the previous issue in
reverse order.

**Acceptance Scenarios**:

1. **Given** the developer has moved from issue A to issue B via a relation, **When**
   they invoke "go back", **Then** issue A becomes current again.
2. **Given** the developer has not moved via a relation in this session, **When** they
   invoke "go back", **Then** they are told there is nowhere to go back to, and
   nothing changes.

---

### User Story 4 - Act on relations from the issue menu (Priority: P3)

The relation commands are reachable from the same menu that already offers claim,
close, comment and assign, so a developer who knows that menu discovers navigation
without reading documentation.

**Why this priority**: Pure discoverability. The commands work without it; they are
merely harder to find.

**Independent Test**: Open the issue menu on an issue with a parent and a blocker and
confirm the relation entries are present, are labelled with what they will act on, and
are visibly unavailable when the issue at point has no such relation.

**Acceptance Scenarios**:

1. **Given** point is on an issue with a parent, **When** the issue menu is opened,
   **Then** it offers an entry that moves to the parent.
2. **Given** point is on an issue with no blockers, **When** the issue menu is opened,
   **Then** the "go to blocker" entry is shown as unavailable rather than silently
   failing when chosen.

---

### Edge Cases

- **Relation to an issue that no longer exists**: the marker states the identifier and
  that it could not be resolved; navigating to it reports the failure instead of
  opening an empty view.
- **Cycles**: A blocks B and B blocks A. Marking and navigation both still work; no
  command loops, and the display shows each issue's own relations once.
- **Deep chains**: an issue five levels below the top of a hierarchy shows only its
  immediate parent, not the whole ancestry; the developer walks up one step at a time.
- **Large fan-out**: an issue that 40 others depend on is summarised by count, not
  listed in full, and the choice prompt remains usable.
- **Blocked issue never listed**: a blocked issue that is neither claimed nor ready is
  not listed, as today. It is still reachable by navigating to it as another issue's
  blocker, and its own relations are shown in its detail view.
- **Ready issue has no live blockers**: an issue in the "Ready" group is by definition
  unblocked, so it can carry a parent mark and a dependents mark but never a blocker
  mark.
- **Tracker unreachable or erroring**: the relation information is absent and the
  existing error reporting for the section is used; relations never turn a working
  section into a broken one.
- **Refresh during navigation**: an issue that disappears from the listing between
  display and navigation (someone closed it) reports that, rather than moving point to
  an unrelated entry.
- **Repository without a tracker**: nothing changes; no command, marker or menu entry
  appears.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST show, for each issue listed in the repository's issue
  section, the identifier and title of that issue's parent when it has one.
- **FR-002**: The system MUST show, for each issue listed, the identifier, status and
  title of each issue that currently blocks it.
- **FR-003**: The system MUST treat a dependency on a closed issue as not blocking, so
  that only live obstacles are marked.
- **FR-004**: The system MUST show, for each issue listed, an indication that other
  issues depend on it, including how many, as far as the listing itself reports it.
  The tracker's listing counts only issues joined by a blocking dependency, not an
  issue's children; the mark says what the listing knows and the navigation asks the
  question that knows more, so a parent's children stay reachable even when the
  parent carries no mark.
- **FR-005**: The system MUST add no visual weight to an issue that has no relations:
  such an issue's entry MUST be unchanged from its current form.
- **FR-006**: Users MUST be able to move from the issue at point to its parent with a
  single command, without typing an identifier.
- **FR-007**: Users MUST be able to move from the issue at point to one of its
  blockers with a single command, choosing among them when there is more than one.
- **FR-008**: Users MUST be able to move from the issue at point to one of the issues
  that depend on it or are its children, choosing among them when there is more than
  one.
- **FR-009**: When the destination issue is present in the current listing, the system
  MUST move point to it there and reveal it, rather than opening a separate view.
- **FR-010**: When the destination issue is not present in the current listing, the
  system MUST open its full detail view.
- **FR-011**: The relation commands MUST operate on the issue shown by a full detail
  view when invoked from one, so navigation continues from wherever the developer is.
- **FR-012**: When the requested relation does not exist for the issue at point, the
  system MUST say so and leave the buffer, point and window configuration unchanged.
- **FR-013**: Users MUST be able to return to the issue they navigated from, repeatedly,
  in reverse order of the jumps they made.
- **FR-014**: The relation commands MUST appear in the existing per-issue menu, each
  labelled with the relation it follows, and MUST be shown as unavailable when the
  issue at point has no such relation.
- **FR-015**: The system MUST report a relation that points at a missing or unreadable
  issue as unresolved, both when marking and when navigating, and MUST NOT fail the
  surrounding display.
- **FR-016**: The system MUST summarise rather than enumerate relations beyond a
  configurable threshold, so that a heavily depended-upon issue cannot dominate the
  listing.
- **FR-017**: Relation information MUST come from the tracker's own dependency
  resolution, not from a second interpretation of the stored data, so that what is
  marked as blocking agrees with what the tracker itself considers blocking.
- **FR-018**: The system MUST NOT make the issue section noticeably slower to draw
  than it is today.
- **FR-019**: The system MUST NOT change which issues the section lists. The groups
  stay "In progress" and "Ready"; no group for blocked issues is added, and no issue
  that is invisible today becomes visible. Relations are marked on the issues already
  listed and nowhere else.

### Key Entities

- **Issue**: the unit of work the tracker holds. Already has identifier, title,
  status, priority, assignee and description. Relevant here for the relations it
  takes part in.
- **Parent relation**: an issue's membership in a larger issue. An issue has at most
  one parent and any number of children.
- **Blocking relation**: a directed dependency stating that one issue cannot proceed
  until another is closed. An issue has any number of blockers and any number of
  dependents. A dependency whose target is closed is not a blocker.
- **Relation marker**: the part of an issue's entry that states its relations —
  present only when the issue has any.
- **Navigation history**: the trail of issues the developer moved through by
  following relations, used to walk back. Lives only for the current editing session.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can tell whether any listed issue has a parent or a live
  blocker without invoking a command or opening another view — 100% of listed issues
  that have such relations are marked.
- **SC-002**: Moving from an issue to its parent or to a chosen blocker takes at most
  two keystrokes, and never requires typing or pasting an identifier.
- **SC-003**: Following a chain of three relations and returning to the starting issue
  takes under 15 seconds and ends with the starting issue current.
- **SC-004a**: When no issue the section lists has a parent, a blocker or a
  dependent, the section asks the tracker for nothing beyond what it asks for today
  and draws within 5% of today's time — a tracker without relations pays nothing for
  this feature.
- **SC-004b**: When listed issues do have relations, the section makes at most two
  requests beyond today's, and that number does not grow with the number of issues
  listed or held by the tracker. Worst case must stay under 0.6 seconds to draw on a
  tracker of the size this repository's has reached.
- **SC-005**: No issue without relations gains a line, a column or an indentation
  level relative to today's display, and the section lists exactly the same issues it
  listed before the feature.
- **SC-006**: Every failure case — missing relation, unresolved target, tracker error
  — produces a message naming the issue and the problem, and leaves the display in a
  usable state; zero cases produce an empty buffer or a raw internal error.

## Assumptions

- The tracker already records both parent-child and blocking relations and can report
  them per issue, together with the related issue's status; no new relation kinds are
  introduced by this feature.
- "Blocker" means an open issue this one depends on. Resolution of what counts as
  blocking is the tracker's, not this feature's.
- Relations are read at the same moments the issue listing is already read — on
  display and on refresh — and are not polled separately.
- The tracker's cheap listing does not count an issue's children among its
  dependents; only the per-issue query does. The dependents mark therefore reports
  blocking dependents only, and downward navigation asks the per-issue query. Paying
  for an exact child count on every refresh was rejected against SC-004a.
- Only immediate relations are shown. Ancestry and transitive blockers are reached by
  repeated single steps, not displayed at once.
- Navigation history is per editing session and is not persisted.
- The feature changes only how issues are displayed and moved between; it does not add
  a way to create, remove or edit a relation. Editing relations is out of scope for
  this version.
- Which issues the section lists is out of scope. Blocker marks are therefore seen
  mainly on claimed work, since ready issues are unblocked by construction. Surfacing
  blocked issues in the status buffer is a separate decision, deliberately deferred.
- The existing per-issue menu is the discovery surface; no new top-level menu is added.
