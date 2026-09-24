# Contract: the default explore prompt

The default value of `beads-agent-explore-prompt`. `%i` expands to the issue id
(`format-spec`, IGNORE-MISSING). Every numbered requirement below maps to a
clause the text MUST keep if the default is ever reworded; the ERT suite asserts
the presence of the marked phrases so that a rewording which drops one fails.

```text
Explore beads issue %i before any work on it starts.

Read it with `bd show %i`, including its parent, its blockers, the issues that
depend on it and its comments. Then read the parts of this repository the issue
concerns, enough to know how it would be implemented here.

Reply with:
1. Your understanding of what the issue asks for and why.
2. Every decision that has to be made before implementing it, each as a
   question, with the options you see and the one you would choose. If nothing
   needs deciding, say so plainly instead of inventing questions.

Do not implement anything. Do not create, edit or delete files. Do not claim,
update, comment on or close any issue. Do not commit. Do not start any skill or
workflow that implements the issue. After your questions, stop and wait for my
answers: I will choose how the work is done, and with which skills if any.
```

| Clause | Requirement | Asserted phrase |
|--------|-------------|-----------------|
| reads issue through the tracker, with relations and comments | FR-006 | `bd show %i`, `comments` |
| explores the repository | FR-006 | `parts of this repository` |
| understanding + decisions as questions with options | FR-007 | `each as a`, `question` |
| explicit "nothing to decide" | FR-007, US2 AS4 | `say so plainly` |
| no files, no tracker changes, no commits, no skill/workflow | FR-008 | `Do not implement anything`, `Do not commit` |
| stop and wait | FR-008 | `stop and wait` |

Constraints on any value, default or customised:

- The expanded text MUST contain the issue id; otherwise
  `"Beads issue <id>:\n\n"` is prepended (FR-010).
- The first character MUST NOT be `/`, `!` or `#` (Claude Code input prefixes).
  The default satisfies this; a customised value that violates it is the
  developer's choice and is sent as written.
