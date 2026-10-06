"""PreToolUse guard: a `git commit` must commit the index and nothing else.

The ask rule on `git commit` stops at a permission prompt, and the prompt is
where the user reviews the staged diff. That review only means something when
the commit contains exactly what is staged at that moment. This guard denies
the commands that change the index in the same call as the commit:

- `git add`, `git rm` and other staging commands chained with `git commit`
- `git commit -a`, `--include`, `--only`, `--patch`, `--interactive`
- `git commit <pathspec>`, which commits those paths regardless of the index

Reads the PreToolUse payload on stdin. Prints a deny decision, or nothing.
Unparseable input is left alone: the ask rule still prompts for it.
"""

import json
import shlex
import sys

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


def segments(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = ""
    current = []
    for token in lexer:
        if token in OPERATORS:
            if current:
                yield current
            current = []
        else:
            current.append(token)
    if current:
        yield current


def git_subcommand(words):
    """Return (subcommand, args) when `words` runs git, else None."""
    i = 0
    while i < len(words) and (
        "=" in words[i] and not words[i].startswith("-") or words[i] in WRAPPERS
    ):
        i += 1
    if i >= len(words) or words[i] != "git":
        return None
    i += 1
    while i < len(words) and words[i].startswith("-"):
        i += 2 if words[i] in GIT_VALUE_OPTIONS else 1
    if i >= len(words):
        return None
    return words[i], words[i + 1 :]


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


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if payload.get("tool_name") != "Bash":
        return
    command = (payload.get("tool_input") or {}).get("command") or ""
    found = problem(command)
    if not found:
        return
    reason = (
        f"Denied: this command {found}. The user reviews the staged changes "
        "when asked to approve a commit, so the commit must contain exactly "
        "what is staged. Stage first, in its own Bash call (`git add <paths>`). "
        "Then run `git commit` alone, with only a message (`-m`/`-F`): no "
        "`-a`, no pathspecs, no staging commands in the same call."
    )
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
