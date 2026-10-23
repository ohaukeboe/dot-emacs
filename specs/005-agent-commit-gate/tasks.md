---

description: "Task list for Agent Commit Gate"
---

# Tasks: Agent Commit Gate

**Input**: Design documents from `/specs/005-agent-commit-gate/`

**Prerequisites**: plan.md, spec.md, research.md (D1–D9), data-model.md, contracts/, quickstart.md

**Tests**: Constitution I and III, and research D9, require them:
- the cheap check `checks.agent-commit-gate`, Python `unittest` against fixture git repos;
- the opt-in `packages.test-agent-commit-review`, Emacs batch with Magit;
- the manual live-session scenarios Q1–Q12 in [quickstart.md](./quickstart.md).

**Organization**: Grouped by user story (spec.md). US1 = Emacs review (P1), US2 = toggles (P2), US3 = free agent worktrees (P3).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: User story label (US1–US3)

## Path Conventions

This is a single-repo NixOS/Home Manager config, and all paths are relative to
the repo root.

- `git add` every new file before running `nix build` or `nix flake check`.
- Edit `workstation/emacs/config.org`, never the generated `.el`.
- Run `nix fmt` and revert any unrelated churn.
- Do not commit. Stage the files and report them.

---

## Phase 1: Setup

**Purpose**: Create the new files and wire them in, with no behaviour change yet.

- [X] T001 Create `workstation/agents/commit-gate.py` by moving the full contents of `workstation/agents/commit-guard.py` (the parser: `segments`, `git_subcommand`, `commit_problem`, `problem`). Keep its module docstring, rewritten to describe the gate. Then delete `workstation/agents/commit-guard.py` with `git rm`.
- [X] T002 Create `workstation/agents/commit-gate.nix` from `workstation/agents/commit-guard.nix`. Build the package `agent-commit-gate` with `pkgs.writers.writePython3Bin` and the same `flakeIgnore` list. Do **not** register a PreToolUse hook here (D1). Delete `workstation/agents/commit-guard.nix` with `git rm`, and replace `./commit-guard.nix` with `./commit-gate.nix` in the `imports` list of `workstation/agents/default.nix`.
- [X] T003 [P] Create `tests/agent-commit-gate.nix`, a `runCommand` check with `python3` and `git` that runs `python3 -m unittest` on `tests/agent-commit-gate_test.py`, importing the gate module from `workstation/agents/commit-gate.py`. Also create `tests/agent-commit-gate_test.py` with one smoke test. Register it in `flake.nix` `checks` as `agent-commit-gate = nixpkgsFor.${system}.callPackage ./tests/agent-commit-gate.nix { };`, with a one-line comment as `expiring-override` has.

---

## Phase 2: Foundational (blocks all stories)

**Purpose**: The gate runs inside the rewriter chain and reproduces today's behaviour: a prompt for commits, and a deny for a commit that stages in the same call.

- [X] T004 Add the options to `workstation/agents/commit-gate.nix`, exactly as specified in [contracts/nix-options.md](./contracts/nix-options.md):
  - `agents.commitGate.enable`: bool, default `true`;
  - `mainCheckout`: `types.enum [ "ask" "emacs" "deny" ]`, default `"ask"`;
  - `claudeWorktrees`: `types.enum [ "gated" "free" ]`, default `"gated"`;
  - `emacsTimeout`: `types.ints.between 30 3000`, default `1200`.

  Wrap all config in `lib.mkIf cfg.enable`. Write the config JSON `{mainCheckout, claudeWorktrees, emacsTimeout, emacsclient}` to the store with `pkgs.writeText`, with `emacsclient` set to the Emacs package's `bin/emacsclient` path. Expose it as `agents.commitGate.configFile`, an internal read-only option, together with `agents.commitGate.package`.
- [X] T005 Add the `decide` entry point to `workstation/agents/commit-gate.py`, following [contracts/gate-cli.md](./contracts/gate-cli.md):
  - read the payload on stdin and the config from `AGENT_COMMIT_GATE_CONFIG`;
  - always print exactly one `{"decision","reason"}` and exit 0;
  - step 1: a staging problem → `deny` with the existing commit-guard reason text, verbatim;
  - then apply the Nix mode only (`ask` → `ask` "Commit on the user's checkout (mode from nix).", `deny` → `deny` "Agent commits are disabled (mode from nix).");
  - `emacs` → `ask` with "Emacs review not available yet" until US1;
  - any exception → `ask`.

  Keep the old no-argument behaviour out. Only `decide` is supported.
- [X] T006 Update the chain in `workstation/agents/default.nix` (`bashRewriterChain`):
  - Detect a commit with `agent-commit-gate has-commit`, a tiny subcommand added to `commit-gate.py` that exits 0 when any segment is `git commit`.
  - When the original command has a commit, and only when `config.agents.commitGate.enable`, run `AGENT_COMMIT_GATE_CONFIG=<configFile> agent-commit-gate decide <<<"$payload"` on the **original** payload, before the stages loop.
  - Use its `decision`/`reason` as `permissionDecision`/`permissionDecisionReason` in the emitted JSON, together with the chain's `updatedInput`, and skip the generic prefix re-assertion for `git commit` (D2).
  - If the gate's output is empty or invalid, emit `ask` (fail closed).
  - Reference the gate through `lib.getExe config.agents.commitGate.package`.
- [X] T007 Add the hook entry fields in `workstation/agents/default.nix`, on the chain's hook object:
  - `timeout = config.agents.commitGate.emacsTimeout + 60;` when the gate is enabled;
  - `onFailure = "block";` only when `lib.versionAtLeast config.programs.claude-code.package.version "2.1.295"` (D3).
- [X] T008 Add assertions in `workstation/agents/commit-gate.nix`. Each message names the file and the fix.
  - (a) `enable → lib.elem "git commit" config.agents.sensitiveBashPrefixes`;
  - (b) `enable → config.agents.bashRewriters != {}`.
- [X] T009 [P] Add unit tests to `tests/agent-commit-gate_test.py`:
  - port the commit-guard cases: `git add x && git commit`, `-a`, `-am`, `--only`, a pathspec, `--` and `-m msg`, which is allowed;
  - `decide` with mode `ask` gives `ask`, and with mode `deny` gives `deny`;
  - a non-commit command gives `has-commit` exit 1;
  - malformed JSON gives `ask`.
- [X] T010 Verify the foundation. `git add` the new files, run `nix fmt`, `nix flake check`, and `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`. Then inspect the rendered `~/.claude/settings.json` in the build output: there should be exactly one Bash PreToolUse hook (the chain), carrying `timeout`, and `Bash(git commit:*)` should still be in `permissions.ask`.

**Checkpoint**: Today's behaviour is reproduced through the chain, and the staging guard still denies.

---

## Phase 3: User Story 1 - Review and edit the agent's commit in Emacs (P1) 🎯 MVP

**Goal**: In `emacs` mode, a commit request opens Magit with the staged diff and the agent's message. Emacs makes the commit, and the agent gets the outcome as a deny with a reason.

**Independent Test**: Set `agents.commitGate.mainCheckout = "emacs"` in Nix and switch. Then run quickstart Q2, Q3, Q4, Q10 and Q12, plus `nix build .#test-agent-commit-review -L`.

- [X] T011 [US1] Add message extraction to `workstation/agents/commit-gate.py` (D8):
  - join the `-m`/`--message` values with `"\n\n"`;
  - read `-F`/`--file <path>` relative to the target directory;
  - return "unsupported" for `-F -` and for `--amend`, `-C`, `-c`, `--reuse-message`, `--reedit-message`, `--fixup`, `--squash`, `--no-verify`, `-n`, `--allow-empty`, `--author`, `--date`, `--reset-author`, `--no-edit`, `--dry-run` and any unrecognised option.
- [X] T012 [US1] Add target directory resolution to `workstation/agents/commit-gate.py`:
  - start from `payload["cwd"]`;
  - apply a leading `cd X &&` segment, then the commit segment's `-C` values in order, each relative to the previous;
  - return `None` when the commit segment has `--git-dir`, `--work-tree`, or a `GIT_DIR=`/`GIT_WORK_TREE=` assignment, or the command cannot be parsed.

  Shared with US3.
- [X] T013 [US1] Add the review client to `workstation/agents/commit-gate.py`, for the `emacs` branch of `decide`. In order:
  1. If the target is unresolved or the form is unsupported → `ask`, with the reason from the contract.
  2. Check reachability with `emacsclient -a false --eval t` (3 s timeout); failure → `ask` "Emacs not reachable".
  3. `git -C dir diff --cached --quiet` exits 0 → `deny` "Nothing is staged.".
  4. Create `$XDG_RUNTIME_DIR/agent-commit-gate/<tool_use_id>/` (mode 0700) and write `msg` and `request.json` `{dir, gate_pid: os.getpid(), deadline}`.
  5. Call `emacsclient --eval '(agent-commit-gate-review "<dir>" "<req>")'`, with the strings escaped for elisp.
  6. Poll every 0.5 s for `result.json` until `emacsTimeout`. On timeout, call `(agent-commit-gate-review-cancel "<req>")` and deny with the timeout text.
  7. Map `result.json` to the committed or not-committed deny texts in [contracts/gate-cli.md](./contracts/gate-cli.md), verbatim.
  8. Remove the request directory.
- [X] T014 [US1] Add the Emacs side in a new subsection "Agent commit review" under `** Magit` in `workstation/emacs/config.org`, following [contracts/emacs-review.md](./contracts/emacs-review.md):
  - `agent-commit-gate-review DIR REQ`:
    - refuse with `not-committed` "review already open in this repository" if a review is already open for the same repository (track open reviews by toplevel in a hash table);
    - otherwise bind `default-directory` and call `(magit-commit-create (list "--edit" (concat "--file=" REQ "/msg")))`;
    - if that does not return a process, write `not-committed` "magit refused: …";
    - otherwise add a sentinel through `add-function :after (process-sentinel proc)` that, on exit, writes `result.json` atomically (temp file + `rename-file`) and only once: `committed` with `(magit-rev-parse "HEAD")` and the subject on exit 0, or `not-committed` with the reason;
    - raise the frame;
    - return `t`.
  - `agent-commit-gate-review-cancel REQ`: find that request's commit buffer and call `with-editor-cancel` there.
- [X] T015 [US1] Add the stale-request refusal to `workstation/emacs/config.org` (D7). In the commit buffer opened by `agent-commit-gate-review`, install a buffer-local check before finishing. Try `with-editor-pre-finish-hook` first; if that hook cannot abort, use `:before-until` advice on `with-editor-finish` scoped to that buffer. The check reads `REQ/request.json` and refuses when `gate_pid` is not alive (`(process-attributes pid)` is nil) or `deadline` has passed: it cancels instead, writes `not-committed` "request expired", and shows a message. Record in research.md D7 which of the two mechanisms worked.
- [X] T016 [P] [US1] Add unit tests to `tests/agent-commit-gate_test.py`:
  - message joining for two `-m` values, `-F` relative to the target directory, `-F -` being unsupported, and `--amend` being unsupported;
  - target resolution for `cd sub && git commit`, `git -C a -C b commit`, and `GIT_DIR=x git commit` → `None`;
  - the `emacs` branch with a fake `emacsclient` script on `PATH` that writes a canned `result.json`, giving the committed and not-committed deny texts;
  - a fake `emacsclient` that fails `--eval t`, giving `ask`;
  - an empty index, giving `deny` "Nothing is staged.".
- [X] T017 [US1] Create `tests/agent-commit-review.nix`, the opt-in Emacs batch test. Build Emacs with magit and with-editor the way `tests/emacs-sops-save.nix` does, tangle or load the "Agent commit review" block from `workstation/emacs/config.org`, and in a fixture repository:
  - (a) open a review, replace the message, call `with-editor-finish`, and assert that `result.json` is `committed` and `git log -1 --format=%s` is the edited subject;
  - (b) open a review, call `with-editor-cancel`, and assert `not-committed` with no new commit;
  - (c) write a `request.json` with a dead pid, finish, and assert `request expired` with no new commit.

  Register it as `packages.test-agent-commit-review` in `flake.nix`, with the comment `# nix build .#test-agent-commit-review -L`.
- [X] T018 [US1] Validate. Run `nix flake check`, `nix build .#test-agent-commit-review -L`, and the home build. After the user switches, run quickstart Q2, Q3, Q4, Q10 and Q12 with the Nix default temporarily set to `emacs`, then revert it.

**Checkpoint**: The Emacs review works end to end, with the mode chosen in Nix.

---

## Phase 4: User Story 2 - Switch the gate's behaviour quickly (P2)

**Goal**: The mode comes from the env var, then the override file, then the Nix default, and it can be set from Emacs. The agent cannot change it.

**Independent Test**: quickstart Q1, Q5 and Q6.

- [X] T019 [US2] Add mode resolution to `workstation/agents/commit-gate.py` (D4, data-model "Gate mode"). The order is:
  1. `AGENT_COMMIT_GATE`;
  2. the override file, at `$XDG_STATE_HOME/agent-commit-gate/override.json` or `~/.local/state/...` when the variable is unset. Use the key given by the absolute `git rev-parse --path-format=absolute --git-common-dir` of the target, then the key `"*"`;
  3. the Nix `mainCheckout`.

  Ignore an invalid value or an unreadable file and fall through to the next source, noting it in the reason. Each `ask`/`deny` reason names its source (`env`, `override repo`, `override *`, `nix`).
- [X] T020 [US2] Add the deny rules in `workstation/agents/commit-gate.nix`: `programs.claude-code.settings.permissions.deny = [ "Edit(${overridePath})" "Write(${overridePath})" ];`, where `overridePath = "${config.xdg.stateHome}/agent-commit-gate/override.json"`. Check the path-rule syntax against the existing `Edit(...)` rules in `workstation/agents/sandbox.nix`, since absolute paths need the `//` prefix form if Claude Code requires it.
- [X] T021 [P] [US2] Add `agent-commit-gate-set` and `agent-commit-gate-show` in `workstation/emacs/config.org` (the same subsection as T014), following [contracts/emacs-review.md](./contracts/emacs-review.md):
  - `agent-commit-gate-set` prompts for a scope (this repository's common git dir, or `*`) and a mode (`ask`, `emacs`, `deny` or `default`), reads and rewrites the JSON atomically, and deletes the key for `default`;
  - `agent-commit-gate-show` echoes the effective mode and its source. It does not see `AGENT_COMMIT_GATE`, and says so.
- [X] T022 [P] [US2] Add unit tests to `tests/agent-commit-gate_test.py`:
  - precedence env > repo > `*` > nix;
  - an invalid env value falls through;
  - a corrupt JSON file falls through;
  - a repository key matches from a linked worktree, because both share the common dir;
  - the reason names the source.
- [X] T023 [US2] Validate: `nix flake check` and the home build. After the switch, run quickstart Q1, Q5 and Q6.

**Checkpoint**: The gate can be toggled at runtime, and the agent cannot change it.

---

## Phase 5: User Story 3 - Free commits in the agent's own worktrees (P3)

**Goal**: With `claudeWorktrees = "free"`, commits pass with no prompt only in a strictly identified agent worktree.

**Independent Test**: quickstart Q8, Q9 and Q11.

- [X] T024 [US3] Add the worktree classification to `workstation/agents/commit-gate.py` (D5, data-model "Agent worktree"). It uses the T012 target. Run `git -C dir rev-parse --path-format=absolute --absolute-git-dir --git-common-dir --show-toplevel` and require all four:
  - `git_dir != common_dir`;
  - the toplevel is under `dirname(common_dir)/.claude/worktrees/`, compared on resolved real paths;
  - `<git_dir>/CLAUDE_BASE` exists;
  - `git -C dir symbolic-ref -q HEAD` equals `refs/heads/worktree-<basename(toplevel)>`.

  Any error means it is not an agent worktree.
- [X] T025 [US3] Wire it into `decide` in `workstation/agents/commit-gate.py`. After step 1 (staging problem → deny, so FR-018 also applies to worktrees) and before the mode is applied: when `claudeWorktrees == "free"` and the target is an agent worktree → `allow` "Commit in the agent's own worktree <name> on worktree-<name>."
- [X] T026 [P] [US3] Add unit tests to `tests/agent-commit-gate_test.py`. Build fixtures with real `git worktree add`:
  - an agent worktree at `.claude/worktrees/w1` on `worktree-w1` with `CLAUDE_BASE`, giving `allow` when free and the mode when gated;
  - the same without `CLAUDE_BASE`, gated;
  - on another branch, gated;
  - a worktree at `../w2`, gated;
  - the main checkout, gated;
  - `git -C <main> commit` run from inside the agent worktree, gated;
  - `git add x && git commit` in an agent worktree, denied.
- [X] T027 [US3] Validate: `nix flake check`, and the home build with `agents.commitGate.claudeWorktrees = "free"` set in the machine or home config the user chooses. Ask the user where to set it. After the switch, run quickstart Q8, Q9 and Q11.

**Checkpoint**: All three stories work independently.

---

## Phase 6: Polish & Cross-Cutting

- [X] T028 [P] Update the commit rules in `workstation/agents/agents-global.md` (FR-020):
  - commits in the agent's own `.claude/worktrees/<n>` on `worktree-<n>` may be allowed by the gate;
  - a commit denied with "committed by the user in Emacs" is done, and must not be retried;
  - "did not commit" means ask first.

  Keep the existing rule about staging and committing in separate calls.
- [X] T029 [P] Write `docs/adr/0006-agent-commit-gate.md` in the format of `docs/adr/0003-agent-bash-rewriter-chain.md`:
  - the decision: the chain owns the commit decision; permission rules match `updatedInput`, so the static rule is the fail-safe; an unsandboxed hook reaches Emacs and the socket stays hidden;
  - mark that it amends ADR 0003 and ADR 0004, and add an "Amended by 0006" note to both.
- [X] T030 [P] Add the terms "commit gate", "gate mode" and "agent worktree" to `GLOSSARY.md`, in its existing format.
- [X] T031 [P] Check `CLAUDE.md`, `AGENTS.md` and `workstation/agents/*-docs.md` for references to `commit-guard` and update them to `commit-gate`, mirrored in both files (constitution, Documentation parity).
- [X] T032 Run the fail-safe test, quickstart Q7: temporarily make the chain exceed its timeout and confirm that `git commit` still prompts. Record the result in research.md D2. If it fails open, stop and report to the user before going further.
- [ ] T033 Final gate: run `nix fmt` and revert unrelated churn, then `nix flake check`, `nix build .#test-agent-commit-review -L` and the home build. Stage the feature files with `git add` and report the staged list. Do not commit.

---

## Dependencies & Execution Order

- Setup (T001–T003) → Foundational (T004–T010) → the user stories.
- US1 (T011–T018) needs Foundational only. T012 (target resolution) is reused by US3.
- US2 (T019–T023) needs Foundational only. It is independent of US1, because the `emacs` mode simply returns `ask` until US1 lands.
- US3 (T024–T027) needs Foundational and T012. If US1 is skipped, do T012 first.
- Polish (T028–T033) comes after the chosen stories.
- Within `commit-gate.py`, the tasks are sequential (same file): T005 → T011 → T012 → T013 → T019 → T024 → T025.
- Within `config.org`, these are sequential: T014 → T015 → T021.

## Parallel Examples

- Setup: T003 alongside T001 and T002 (different files).
- US1: T016 (tests) alongside T014 and T015 (elisp), after T013.
- US2: T021 (elisp) and T022 (tests) alongside T019 and T020.
- US3: T026 (tests) alongside T024.
- Polish: T028, T029, T030 and T031 together.

## Implementation Strategy

- **MVP**: Phases 1, 2 and 3 (US1). The Nix default stays `ask`; set it to `emacs` to use the review.
- **Increment 2**: US2, a runtime toggle from Emacs, so no rebuild is needed to switch modes.
- **Increment 3**: US3, free agent-worktree commits, off by default.
- Stop at each checkpoint, have the user switch, and run the listed quickstart scenarios before going on.
