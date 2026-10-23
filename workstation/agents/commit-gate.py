"""Commit gate: decides every `git commit` the agent runs through Bash.

The rewriter chain (workstation/agents/default.nix) calls this with the
PreToolUse payload as the agent wrote it, before rtk or the process cap
rewrite it, and only when the command mentions a commit. The chain turns the
decision into the hook's permissionDecision. See
docs/adr/0006-agent-commit-gate.md and specs/005-agent-commit-gate/.

    agent-commit-gate has-commit   exit 0 when a segment runs `git commit`
    agent-commit-gate decide       print {"decision": ..., "reason": ...}

`decide` reads its Nix settings from the JSON file named by
AGENT_COMMIT_GATE_CONFIG. In order:

1. Staging guard. The user reviews the staged diff before approving a commit,
   so the commit must contain exactly the index: a commit that stages in the
   same call (`git add ... && git commit`, `-a`, pathspecs) is denied.
2. A commit in a worktree the agent created, on that worktree's own branch,
   is allowed when `claudeWorktrees` is "free".
3. Otherwise the mode applies: AGENT_COMMIT_GATE, then the override file
   Emacs writes (by repository, then "*"), then the Nix default.
   - ask: the ordinary permission prompt.
   - deny: refused.
   - emacs: Emacs opens a Magit commit buffer with the agent's message and
     the staged diff, and makes the commit itself when the user finishes it.
     The agent's own command is then denied with the outcome as the reason,
     so a single request never commits twice.

Every unexpected failure asks: the gate never lets a commit through that it
could not judge.
"""

import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
import uuid

OPERATORS = {"&&", "||", ";", "|", "&", "|&", "(", ")", "\n"}

# Words that run the rest of the segment as a command.
WRAPPERS = {"env", "command", "nocap", "rtk", "sudo", "time", "nice"}

# git options that take their value as the next word.
GIT_VALUE_OPTIONS = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
}

# Subcommands that change the index.
STAGING = {
    "add",
    "rm",
    "mv",
    "stage",
    "update-index",
    "apply",
    "reset",
    "restore",
    "checkout",
}

# Long commit options that take their value as the next word.
COMMIT_VALUE_LONG = {
    "--message",
    "--file",
    "--reuse-message",
    "--reedit-message",
    "--fixup",
    "--squash",
    "--author",
    "--date",
    "--template",
    "--cleanup",
    "--trailer",
}
# Short commit options that take a value, attached or as the next word.
COMMIT_VALUE_SHORT = set("mFCcSt")
COMMIT_STAGING_LONG = {
    "--all",
    "--include",
    "--only",
    "--patch",
    "--interactive",
    "--pathspec-from-file",
}
COMMIT_STAGING_SHORT = set("aiop")

# git options and environment that point git somewhere other than the
# directory the command runs in. The target is then unknown.
REDIRECTING_GIT_OPTIONS = {"--git-dir", "--work-tree"}
REDIRECTING_ENV = {"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"}

# Commit options the Emacs review reproduces: the message, and noise.
REVIEW_QUIET = {"-q", "--quiet"}

MODES = ("ask", "emacs", "deny")

STAGING_REASON = (
    "Denied: this command {found}. The user reviews the staged changes "
    "when asked to approve a commit, so the commit must contain exactly "
    "what is staged. Stage first, in its own Bash call (`git add <paths>`). "
    "Then run `git commit` alone, with only a message (`-m`/`-F`): no "
    "`-a`, no pathspecs, no staging commands in the same call."
)


# --- Parsing ---------------------------------------------------------------


# A redirection: `>f`, `2>/dev/null`, `>>f`, `<f`, `2>&1`. Group 2 is the
# target when attached; a bare operator takes the next word.
REDIRECT = re.compile(r"^(\d*|&)(?:>>|>&|<&|>\||&>|>|<)(.*)$")


def segments(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = ""
    current = []
    # After a bare redirection operator the next word is its target. shlex
    # splits `2>&1` into `2>`, `&`, `1`, so a lone `&` there is part of the
    # redirection, not a background operator.
    target = None
    for token in lexer:
        if target == "word":
            target = "fd" if token == "&" else None
            continue
        if target == "fd":
            target = None
            continue
        if token in OPERATORS:
            if current:
                yield current
            current = []
        elif REDIRECT.match(token):
            # Not an argument of the command: never a pathspec.
            target = "word" if REDIRECT.match(token).group(2) == "" else None
        else:
            current.append(token)
    if current:
        yield current


def parse_git(words):
    """Return a dict describing a git call, or None when `words` is not one.

    Keys: env (assignments before git), opts (global options as
    (name, value) pairs), sub, args.
    """
    i = 0
    env = {}
    while i < len(words) and (
        "=" in words[i] and not words[i].startswith("-") or words[i] in WRAPPERS
    ):
        if "=" in words[i]:
            name, value = words[i].split("=", 1)
            env[name] = value
        i += 1
    if i >= len(words) or words[i] != "git":
        return None
    i += 1
    opts = []
    while i < len(words) and words[i].startswith("-"):
        word = words[i]
        if word in GIT_VALUE_OPTIONS:
            opts.append((word, words[i + 1] if i + 1 < len(words) else None))
            i += 2
        else:
            name, _, value = word.partition("=")
            opts.append((name, value or None))
            i += 1
    if i >= len(words):
        return None
    return {"env": env, "opts": opts, "sub": words[i], "args": words[i + 1 :]}


def git_subcommand(words):
    """Return (subcommand, args) when `words` runs git, else None."""
    git = parse_git(words)
    return (git["sub"], git["args"]) if git else None


def commit_problem(args):
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            return "passes pathspecs after `--`"
        if arg.startswith("--"):
            name = arg.split("=", 1)[0]
            if name in COMMIT_STAGING_LONG:
                return f"uses `{name}`"
            if name in COMMIT_VALUE_LONG and "=" not in arg:
                i += 1
        elif arg.startswith("-") and len(arg) > 1:
            for pos, flag in enumerate(arg[1:]):
                if flag in COMMIT_STAGING_SHORT:
                    return f"uses `-{flag}`"
                if flag in COMMIT_VALUE_SHORT:
                    # An attached value ends the cluster; otherwise it is the
                    # next word. -S takes no detached value.
                    if pos == len(arg) - 2 and flag != "S":
                        i += 1
                    break
        else:
            return f"names the path `{arg}`"
        i += 1
    return None


def problem(command):
    """The staging guard: a reason to deny, or None."""
    try:
        parsed = [git_subcommand(s) for s in segments(command)]
    except ValueError:
        return None
    gits = [p for p in parsed if p]
    commits = [args for sub, args in gits if sub == "commit"]
    if not commits:
        return None
    staging = sorted({sub for sub, _ in gits if sub in STAGING})
    if staging:
        return f"runs `git {staging[0]}` in the same call as `git commit`"
    for args in commits:
        found = commit_problem(args)
        if found:
            return f"`git commit` {found}"
    return None


def has_commit(command):
    try:
        return any(
            (git := parse_git(s)) and git["sub"] == "commit"
            for s in segments(command)
        )
    except ValueError:
        # Unparseable but mentions a commit: let `decide` ask.
        return "commit" in command


def _plain(word):
    """A word the gate can resolve as a path: no expansion left in it."""
    return word and not any(c in word for c in "$`*?[~")


def commit_request(command, cwd):
    """Describe the single commit in `command`.

    Returns (target, args, why). `target` is the absolute directory git
    commits in, or None with `why` saying why it is unknown. A command whose
    only other segments are `cd <dir>` keeps a known target; anything else
    alongside the commit (a push, a second commit) makes it a compound
    command, which the gate never allows or reviews on its own.
    """
    try:
        segs = list(segments(command))
    except ValueError:
        return None, None, "the command could not be parsed"
    if not cwd or not os.path.isabs(cwd):
        return None, None, "the hook payload has no working directory"
    directory = cwd
    commit = None
    for words in segs:
        git = parse_git(words)
        if git and git["sub"] == "commit":
            if commit is not None:
                return None, None, "the command runs more than one commit"
            commit = git
            continue
        if commit is None and words[0] == "cd" and len(words) == 2:
            if not _plain(words[1]) or words[1] == "-":
                return None, None, "`cd` names a directory the gate cannot resolve"
            directory = os.path.normpath(os.path.join(directory, words[1]))
            continue
        return None, None, "the commit is part of a compound command"
    if commit is None:
        return None, None, "the command runs no commit"
    if REDIRECTING_ENV & commit["env"].keys():
        return None, None, "the commit sets git's directory through the environment"
    for name, value in commit["opts"]:
        if name in REDIRECTING_GIT_OPTIONS:
            return None, None, f"the commit uses `{name}`"
        if name == "-C":
            if not _plain(value):
                return None, None, "`git -C` names a directory the gate cannot resolve"
            directory = os.path.normpath(os.path.join(directory, value))
    return directory, commit, None


def commit_message(args, directory):
    """Return (message, unsupported) for a review in Emacs.

    The review reproduces only a plain commit of the index with a message:
    any other option makes it unsupported, so the user gets the ordinary
    prompt instead of a review that would differ from the agent's command.
    """
    paragraphs = []
    file_message = None
    i = 0

    def value_after(i, attached):
        if attached:
            return attached, i
        if i + 1 >= len(args):
            raise IndexError
        return args[i + 1], i + 1

    try:
        while i < len(args):
            arg = args[i]
            if arg in REVIEW_QUIET:
                pass
            elif arg.startswith("--message"):
                value, i = value_after(i, arg.partition("=")[2])
                paragraphs.append(value)
            elif arg.startswith("--file"):
                value, i = value_after(i, arg.partition("=")[2])
                file_message = value
            elif arg.startswith("-") and not arg.startswith("--") and len(arg) > 1:
                flags = arg[1:]
                for pos, flag in enumerate(flags):
                    if flag == "q":
                        continue
                    if flag in "mF":
                        value, i = value_after(i, flags[pos + 1 :])
                        if flag == "m":
                            paragraphs.append(value)
                        else:
                            file_message = value
                        break
                    return None, f"`-{flag}`"
            else:
                return None, f"`{arg.split('=', 1)[0]}`"
            i += 1
    except IndexError:
        return None, "an option without its value"
    if file_message is not None:
        if paragraphs:
            return None, "both `-m` and `-F`"
        if file_message == "-":
            return None, "`-F -`"
        path = os.path.join(directory, file_message)
        try:
            with open(path, encoding="utf-8") as f:
                return f.read(), None
        except OSError:
            return None, f"an unreadable message file `{file_message}`"
    if not paragraphs:
        return None, "no message"
    # git joins several -m values as separate paragraphs.
    return "\n\n".join(paragraphs), None


# Characters that, unquoted, make the shell do more than run the words the
# gate parsed: expansion, substitution, redirection, globbing, escapes, other
# operators. `&` is allowed only as part of `&&`.
SHELL_SPECIAL = set("$`<>()|;*?[]{}~!\\\n")
# Inside double quotes only these still expand.
DOUBLE_QUOTE_SPECIAL = set("$`")


def shell_inert(command):
    """True when the shell would run `command` as plain words joined by `&&`.

    Follows quoting: single-quoted text is literal, double-quoted text is
    literal except for `$` and backticks, and unquoted text may not contain
    any SHELL_SPECIAL character. A commit message with a `Co-Authored-By:
    Name <email>` trailer and newlines inside quotes therefore passes, while
    `"$(cmd)"` or an unquoted redirect does not.
    """
    quote = None
    i = 0
    while i < len(command):
        c = command[i]
        if quote == "'":
            if c == "'":
                quote = None
        elif quote == '"':
            if c == "\\":
                i += 1  # \" \\ \$ \` are literal; the next char is consumed
            elif c in DOUBLE_QUOTE_SPECIAL:
                return False
            elif c == '"':
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "&":
            if command[i : i + 2] != "&&":
                return False
            i += 1
        elif c in SHELL_SPECIAL:
            return False
        i += 1
    return quote is None


def plain_commit(command, commit, directory):
    """True when an allow would cover exactly the commit the gate judged.

    An allow applies to the whole command text, so it is given only to the
    plainest form: `git [-C dir] commit -m ...`, optionally after `cd dir &&`,
    with no wrapper, environment assignment, git option other than -C,
    commit option other than -m/--message/-q, and nothing the shell would
    expand, substitute or redirect (see shell_inert). A message using `$` or
    a backtick, even quoted, gets the mode instead.
    """
    if not shell_inert(command):
        return False
    if commit["env"] or any(name != "-C" for name, _ in commit["opts"]):
        return False
    # Exactly `[cd dir &&] git ... commit ...`. commit_request already
    # rejects anything else; this keeps the allow's scope stated here too.
    try:
        segs = list(segments(command))
    except ValueError:
        return False
    if not 1 <= len(segs) <= 2 or segs[-1][0] != "git":
        return False
    if len(segs) == 2 and (segs[0][0] != "cd" or len(segs[0]) != 2):
        return False
    args = commit["args"]
    if any(a.startswith(("-F", "--file")) for a in args):
        return False
    _, unsupported = commit_message(args, directory)
    return unsupported is None


# --- Repository facts ------------------------------------------------------


def git(directory, *args):
    result = subprocess.run(
        ["git", "-C", directory, *args],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.returncode, result.stdout.strip()


def repo_dirs(directory):
    """Return (git_dir, common_dir, toplevel) as absolute paths, or None."""
    code, out = git(
        directory,
        "rev-parse",
        "--path-format=absolute",
        "--absolute-git-dir",
        "--git-common-dir",
        "--show-toplevel",
    )
    lines = out.splitlines()
    if code != 0 or len(lines) != 3:
        return None
    return tuple(os.path.realpath(p) for p in lines)


def agent_worktree(directory):
    """The worktree's name when `directory` is a worktree the agent created.

    All of these must hold, or the commit is treated as the user's:
    - it is a linked worktree, not the main checkout;
    - it lies in `.claude/worktrees/` of the main checkout, where Claude
      Code creates its worktrees;
    - it carries the CLAUDE_BASE marker Claude Code writes into the
      worktree's git dir;
    - HEAD is the branch Claude Code created for it, `worktree-<name>`, not
      one of the user's branches checked out there.
    """
    try:
        dirs = repo_dirs(directory)
        if not dirs:
            return None
        git_dir, common_dir, toplevel = dirs
        if git_dir == common_dir:
            return None
        root = os.path.join(os.path.dirname(common_dir), ".claude", "worktrees")
        if os.path.dirname(toplevel) != root:
            return None
        if not os.path.isfile(os.path.join(git_dir, "CLAUDE_BASE")):
            return None
        name = os.path.basename(toplevel)
        code, head = git(directory, "symbolic-ref", "-q", "HEAD")
        if code != 0 or head != f"refs/heads/worktree-{name}":
            return None
        return name
    except (OSError, subprocess.SubprocessError):
        return None


# --- Mode ------------------------------------------------------------------


def override_path():
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "agent-commit-gate", "override.json")


def resolve_mode(config, directory):
    """Return (mode, source, notes)."""
    notes = []
    env = os.environ.get("AGENT_COMMIT_GATE")
    if env:
        if env in MODES:
            return env, "env AGENT_COMMIT_GATE", notes
        notes.append(f"ignored AGENT_COMMIT_GATE={env!r}")
    overrides = {}
    try:
        with open(override_path(), encoding="utf-8") as f:
            overrides = json.load(f)
        if not isinstance(overrides, dict):
            notes.append("ignored the override file: not a JSON object")
            overrides = {}
    except FileNotFoundError:
        pass
    except (OSError, ValueError):
        notes.append("ignored the unreadable override file")
    keys = []
    if directory and overrides:
        dirs = repo_dirs(directory)
        if dirs:
            keys.append((dirs[1], "override for this repository"))
    keys.append(("*", "override *"))
    for key, source in keys:
        value = overrides.get(key)
        if value is None:
            continue
        if value in MODES:
            return value, source, notes
        notes.append(f"ignored {source} {value!r}")
    return config["mainCheckout"], "nix", notes


# --- Emacs review ----------------------------------------------------------


def elisp_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emacsclient(config, form, timeout):
    return subprocess.run(
        [config["emacsclient"], "-a", "false", "--eval", form],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def review(config, payload, directory, message):
    """Run the review in Emacs. Returns (decision, reason)."""
    try:
        if emacsclient(config, "t", 3).returncode != 0:
            return "ask", "Emacs is not reachable for the commit review."
    except (OSError, subprocess.SubprocessError):
        return "ask", "Emacs is not reachable for the commit review."

    code, _ = git(directory, "diff", "--cached", "--quiet")
    if code == 0:
        return "deny", "Nothing is staged. Stage the changes first, in their own Bash call."

    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        return "ask", "XDG_RUNTIME_DIR is unset, so the commit review cannot run."
    request_id = re.sub(r"[^A-Za-z0-9_-]", "", payload.get("tool_use_id") or "")
    request = os.path.join(
        runtime, "agent-commit-gate", request_id or uuid.uuid4().hex
    )
    timeout = config["emacsTimeout"]
    os.makedirs(os.path.dirname(request), mode=0o700, exist_ok=True)
    os.mkdir(request, 0o700)

    def cancel(*_):
        try:
            emacsclient(
                config,
                f"(agent-commit-gate-review-cancel {elisp_string(request)})",
                5,
            )
        except (OSError, subprocess.SubprocessError):
            pass

    def interrupted(signum, _frame):
        # Claude Code stopped waiting (interrupt or hook timeout): withdraw
        # the review so a late finish cannot commit behind the agent's back.
        cancel()
        shutil.rmtree(request, ignore_errors=True)
        sys.exit(128 + signum)

    try:
        with open(os.path.join(request, "msg"), "w", encoding="utf-8") as f:
            f.write(message)
        with open(os.path.join(request, "request.json"), "w", encoding="utf-8") as f:
            json.dump(
                {
                    "dir": directory,
                    "gate_pid": os.getpid(),
                    "deadline": int(time.time()) + timeout,
                },
                f,
            )
        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            signal.signal(signum, interrupted)

        opened = emacsclient(
            config,
            f"(agent-commit-gate-review {elisp_string(directory)} {elisp_string(request)})",
            10,
        )
        if opened.returncode != 0:
            return "ask", (
                "Emacs could not open the commit review "
                f"({(opened.stderr or opened.stdout).strip()[:200]})."
            )

        result_file = os.path.join(request, "result.json")
        deadline = time.monotonic() + timeout
        while not os.path.exists(result_file):
            if time.monotonic() > deadline:
                cancel()
                return "deny", (
                    f"The Emacs review timed out after {timeout}s and was "
                    "cancelled. Nothing was committed. Ask the user before "
                    "trying again."
                )
            time.sleep(0.5)
        with open(result_file, encoding="utf-8") as f:
            result = json.load(f)
    finally:
        shutil.rmtree(request, ignore_errors=True)

    if result.get("status") == "committed":
        return "deny", (
            "The user reviewed and committed this in Emacs as "
            f"{result.get('sha', '?')} \"{result.get('subject', '')}\". "
            "The commit is done; do not run git commit again."
        )
    return "deny", (
        f"The user did not commit ({result.get('reason', 'no reason given')}). "
        "Nothing was committed. Ask the user before trying again."
    )


# --- Decision --------------------------------------------------------------


def decide(payload, config):
    command = (payload.get("tool_input") or {}).get("command") or ""
    found = problem(command)
    if found:
        return "deny", STAGING_REASON.format(found=found)

    directory, commit, why = commit_request(command, payload.get("cwd"))

    if (
        directory
        and config["claudeWorktrees"] == "free"
        and plain_commit(command, commit, directory)
    ):
        name = agent_worktree(directory)
        if name:
            return "allow", (
                f"Commit in the agent's own worktree {name} on worktree-{name}."
            )

    mode, source, notes = resolve_mode(config, directory)
    note = f" ({'; '.join(notes)})" if notes else ""
    if mode == "deny":
        return "deny", f"Agent commits are disabled (mode from {source}){note}."
    if mode == "ask":
        return "ask", f"Commit on the user's checkout (mode from {source}){note}."

    # emacs
    if not directory:
        return "ask", f"{why[0].upper()}{why[1:]}, so Emacs cannot review it."
    message, unsupported = commit_message(commit["args"], directory)
    if unsupported:
        return "ask", (
            f"The commit uses {unsupported}, which the Emacs review cannot "
            "show faithfully."
        )
    if any(name == "-c" for name, _ in commit["opts"]):
        return "ask", "The commit sets git config with `-c`, which the Emacs review cannot show faithfully."
    return review(config, payload, directory, message)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = None

    if action == "has-commit":
        command = ((payload or {}).get("tool_input") or {}).get("command") or ""
        sys.exit(0 if payload and has_commit(command) else 1)

    if action != "decide":
        print("usage: agent-commit-gate has-commit|decide", file=sys.stderr)
        sys.exit(2)

    try:
        if payload is None:
            raise ValueError("the hook payload is not JSON")
        with open(os.environ["AGENT_COMMIT_GATE_CONFIG"], encoding="utf-8") as f:
            config = json.load(f)
        decision, reason = decide(payload, config)
    except Exception as e:  # noqa: BLE001 - every failure must ask
        decision, reason = "ask", f"The commit gate failed ({type(e).__name__}: {e})."
    json.dump({"decision": decision, "reason": reason}, sys.stdout)


if __name__ == "__main__":
    main()
