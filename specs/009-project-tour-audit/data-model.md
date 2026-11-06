# Data Model: Project Tours and Project Audits

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Extends [006's data model](../006-review-walkthrough/data-model.md). Only what
differs for `kind` `tour` and `audit` is listed. The file format is in
[contracts/walkthrough-file.md](./contracts/walkthrough-file.md).

## Walkthrough (extended)

| Field     | Meaning                         | Rule                                     |
|-----------|---------------------------------|------------------------------------------|
| `kind`    | `changes`, `tour` or `audit`    | absent means `changes`                   |
| `commit`  | Commit described (draft only)   | tour/audit: resolves to a commit         |
| `base`    | = `commit`                      | tour/audit: set by Emacs at install      |
| `head`    | = `commit`                      | tour/audit: set by Emacs at install      |
| `branch`  | Branch                          | tour/audit: absent                       |
| `area`    | Path the run covered            | optional; absent = whole project         |
| `skipped` | What was not covered            | optional array of non-empty strings      |
| `steps`   | Steps in reading order          | at least one                             |

**Identity**: `(git-common-dir, kind, area)`; installed as `:<kind>.json` or
`:<kind>:<area>.json` (research R6). Re-install replaces, marks and all.

**Derived**: *Moved*: `HEAD` is not `commit`. *Gone*: `commit` no longer
exists.

## Step (extended)

| Field         | Meaning                       | Rule (tour/audit)                      |
|---------------|-------------------------------|----------------------------------------|
| `title`       | The concept or area           | non-empty                              |
| `explanation` | Markdown, diagrams fenced     | non-empty; fenced lines ≤ 90 columns   |
| `files`       | Code excerpts                 | optional; each `{file, ranges}`        |
| `findings`    | Findings                      | tour: empty; audit: may be empty       |

Tour: step 1 is the overview and its explanation holds at least one fenced
block (the diagram).

## Code excerpt

One `{file, ranges}` entry: lines `[start, end]` of `file` at `commit`.

| Rule                                                        | Source |
|-------------------------------------------------------------|--------|
| `file` exists at `commit` and is text                       | FR-005 |
| `1 <= start <= end <= ` line count of `file` at `commit`    | FR-005 |
| `end - start + 1 <= 80`                                     | FR-024 |

**Shown**: as one synthetic context-only hunk per merged run of ranges
(research R2). In an audit, each anchored finding adds its lines ± 3 to the
step's excerpts (R8).

## Finding (extended, audit only)

| Field              | Meaning                   | Rule                                 |
|--------------------|---------------------------|--------------------------------------|
| `type`             | `defect` or `smell`       | required                             |
| `failure_scenario` | Inputs, wrong result      | required for `defect`                |
| `verdict`          | Checked against code      | `defect`: `CONFIRMED` or `PLAUSIBLE` |
| `anchor`           | `{file, line, end_line?}` | lines exist at `commit`              |

An anchor's file need not be among the step's `files` (research R8).

`side` is meaningless without a diff and must be absent. States, replies and
follow-ups are unchanged from 006.

## Review comment (unchanged shape)

In a tour or audit, a hunk comment's `:where` is `code at <commit>`
(research R9); `:new` and `:old` are the same file lines. Step and passage
comments, diagrams included, are 006's step comments.

## Hand-off item (unchanged shape)

For an audit finding, `:where` is `code at <commit>` and `:patch` the
synthetic hunk of the anchored lines ± 3. `:type` is added and printed after
the severity.
