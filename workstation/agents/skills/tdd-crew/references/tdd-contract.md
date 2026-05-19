# TDD Contract for tdd-crew Members

Every implementer role (Frontend Developer, Backend Architect, Mobile App Builder, Security Engineer) must follow this contract for each vertical slice.

## The Cycle

```
RED  →  GREEN  →  REFACTOR  →  Report to lead
```

This is not a suggestion. Writing production code before a failing test exists violates the contract and the lead must ask you to undo and restart.

## RED phase

Write a test (or tests) that:
- Describe **user-visible behaviour** for this slice, not implementation details
- Fail when you run them right now (that is what makes them RED)
- Would still pass if you rewrote the internals entirely

Run the tests. Confirm they fail. Report the failing test output to the lead before writing any production code.

**Never skip RED.** If you think "the test is trivial" — write it anyway. If you think "there's nothing to test" — write a test for the acceptance criterion anyway. The test is the specification.

## GREEN phase

Write the **minimum** production code needed to make the failing test pass.

- No speculative features
- No "while I'm here" refactors
- No code not required by the current test

Run the tests. Confirm they are all green. Nothing else is in scope until they are.

## REFACTOR phase

With tests green:
- Remove duplication
- Improve names
- Simplify logic
- Extract seams for future extension

Do NOT add features. Do NOT change behaviour. Tests must stay green throughout.

## Vertical slices, not horizontal layers

Each cycle covers one user-visible behaviour end to end. Do not write all tests first then all code. Do not write all backend code then all frontend code. One behaviour → RED → GREEN → REFACTOR → next behaviour.

## Consulting the global /tdd skill

The global `/tdd` skill has detailed reference material on:
- Mocking strategies (when to mock, when not to)
- Interface design for testability
- Deep vs shallow modules
- Refactoring patterns

Consult it when you hit a hard design decision. Do not let it slow you down on routine cycles.

## Handoff signal

When a slice cycle is complete, report using your role's output format (see `role-*.md`). Include:
- Test file paths (RED → GREEN)
- Files changed
- Any design decisions the lead should know about
