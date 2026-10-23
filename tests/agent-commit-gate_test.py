"""Unit tests for workstation/agents/commit-gate.py.

Run by tests/agent-commit-gate.nix, which copies the gate in as
commit_gate.py. Fixture repositories are real git repositories, and the
agent worktree fixture is made by `git worktree add` with the marker Claude
Code writes. Emacs is a fake emacsclient on a path in the config.
"""

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest import mock

import commit_gate as gate

BASE_CONFIG = {
    "mainCheckout": "ask",
    "claudeWorktrees": "gated",
    "emacsTimeout": 30,
    "emacsclient": "/nonexistent/emacsclient",
}


def sh(cwd, *args):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True)


def payload(command, cwd, tool_use_id="toolu_test"):
    return {
        "tool_name": "Bash",
        "tool_input": {"command": command},
        "cwd": cwd,
        "tool_use_id": tool_use_id,
    }


class Fixture(unittest.TestCase):
    """A repository with one commit, a staged change and an agent worktree."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = os.path.realpath(self.tmp.name)
        self.state = os.path.join(root, "state")
        self.runtime = os.path.join(root, "runtime")
        os.makedirs(self.runtime, mode=0o700)
        env = mock.patch.dict(
            os.environ,
            {"XDG_STATE_HOME": self.state, "XDG_RUNTIME_DIR": self.runtime},
        )
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("AGENT_COMMIT_GATE", None)

        self.repo = os.path.join(root, "repo")
        os.makedirs(os.path.join(self.repo, "sub"))
        sh(self.repo, "git", "init", "-q")
        for name in ("a.txt", "sub/b.txt"):
            with open(os.path.join(self.repo, name), "w") as f:
                f.write("one\n")
        sh(self.repo, "git", "add", ".")
        sh(self.repo, "git", "commit", "-qm", "init")

        self.wt = os.path.join(self.repo, ".claude", "worktrees", "w1")
        sh(self.repo, "git", "worktree", "add", "-q", "-b", "worktree-w1", self.wt)
        git_dir = subprocess.run(
            ["git", "-C", self.wt, "rev-parse", "--absolute-git-dir"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        with open(os.path.join(git_dir, "CLAUDE_BASE"), "w") as f:
            f.write("base\n")
        self.wt_git_dir = git_dir

    def stage(self, directory):
        with open(os.path.join(directory, "a.txt"), "a") as f:
            f.write("more\n")
        sh(directory, "git", "add", "a.txt")

    def decide(self, command, cwd=None, **config):
        return gate.decide(payload(command, cwd or self.repo), {**BASE_CONFIG, **config})

    def set_override(self, mapping):
        path = gate.override_path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(mapping if isinstance(mapping, str) else json.dumps(mapping))


class StagingGuard(Fixture):
    def test_denies_staging_in_the_same_call(self):
        for command in (
            "git add x && git commit -m m",
            "git commit -a -m m",
            "git commit -am m",
            "git commit --only -m m x",
            "git commit -m m a.txt",
            "git commit -m m -- a.txt",
        ):
            with self.subTest(command=command):
                decision, reason = self.decide(command)
                self.assertEqual(decision, "deny")
                self.assertIn("Stage first", reason)

    def test_plain_commit_is_not_denied_by_the_guard(self):
        self.assertEqual(self.decide("git commit -m m")[0], "ask")

    def test_redirections_are_not_pathspecs(self):
        for command in (
            "git commit -m m 2>/dev/null",
            "git commit -m m > out",
            "git commit -m m 2>&1",
            "git commit -m m >>log 2>&1",
            "git commit -m m &>/dev/null",
        ):
            with self.subTest(command=command):
                self.assertEqual(self.decide(command)[0], "ask")
                directory, _, why = gate.commit_request(command, self.repo)
                self.assertEqual(directory, self.repo, why)

    def test_guard_applies_in_a_free_agent_worktree(self):
        decision, _ = self.decide(
            "git add a.txt && git commit -m m", cwd=self.wt, claudeWorktrees="free"
        )
        self.assertEqual(decision, "deny")


class HasCommit(unittest.TestCase):
    def test_detects_commit_segments(self):
        self.assertTrue(gate.has_commit("cd x && git -C y commit -m m"))
        self.assertTrue(gate.has_commit("rtk git commit -m m"))
        self.assertFalse(gate.has_commit("git log --grep commit"))
        self.assertFalse(gate.has_commit("echo commit"))

    def test_main_exit_codes(self):
        script = os.path.join(os.path.dirname(gate.__file__), "commit_gate.py")
        for command, code in (("git commit -m m", 0), ("ls", 1)):
            result = subprocess.run(
                [sys.executable, script, "has-commit"],
                input=json.dumps(payload(command, "/")),
                text=True,
            )
            self.assertEqual(result.returncode, code)

    def test_decide_asks_on_malformed_input(self):
        script = os.path.join(os.path.dirname(gate.__file__), "commit_gate.py")
        result = subprocess.run(
            [sys.executable, script, "decide"],
            input="not json",
            text=True,
            capture_output=True,
        )
        self.assertEqual(json.loads(result.stdout)["decision"], "ask")


class Target(Fixture):
    def test_resolution(self):
        cases = {
            "git commit -m m": self.repo,
            "cd sub && git commit -m m": os.path.join(self.repo, "sub"),
            "git -C sub -C .. commit -m m": self.repo,
            "cd sub && git -C .. commit -m m": self.repo,
        }
        for command, expected in cases.items():
            with self.subTest(command=command):
                directory, _, why = gate.commit_request(command, self.repo)
                self.assertEqual(directory, expected, why)

    def test_unresolvable(self):
        for command in (
            "GIT_DIR=x git commit -m m",
            "git --git-dir=x commit -m m",
            "git --work-tree x commit -m m",
            "cd $HOME && git commit -m m",
            "git -C ~/x commit -m m",
            "git commit -m m && git push",
            "git commit -m a; git commit -m b",
        ):
            with self.subTest(command=command):
                directory, _, why = gate.commit_request(command, self.repo)
                self.assertIsNone(directory)
                self.assertTrue(why)


class Message(Fixture):
    def message(self, command):
        _, commit, _ = gate.commit_request(command, self.repo)
        return gate.commit_message(commit["args"], self.repo)

    def test_joins_paragraphs(self):
        self.assertEqual(
            self.message("git commit -m 'feat: x' -m 'Body.'"), ("feat: x\n\nBody.", None)
        )
        self.assertEqual(self.message("git commit -qm s --message=b"), ("s\n\nb", None))

    def test_file_relative_to_target(self):
        with open(os.path.join(self.repo, "sub", "msg"), "w") as f:
            f.write("from file\n")
        _, commit, _ = gate.commit_request("git -C sub commit -F msg", self.repo)
        self.assertEqual(
            gate.commit_message(commit["args"], os.path.join(self.repo, "sub")),
            ("from file\n", None),
        )

    def test_unsupported(self):
        for command in (
            "git commit -F -",
            "git commit --amend -m m",
            "git commit -n -m m",
            "git commit --no-verify -m m",
            "git commit -C HEAD",
            "git commit --fixup HEAD",
            "git commit -s -m m",
            "git commit",
            "git commit -m",
        ):
            with self.subTest(command=command):
                message, unsupported = self.message(command)
                self.assertIsNone(message)
                self.assertTrue(unsupported)


class Modes(Fixture):
    def test_nix_default(self):
        self.assertEqual(self.decide("git commit -m m")[0], "ask")
        decision, reason = self.decide("git commit -m m", mainCheckout="deny")
        self.assertEqual(decision, "deny")
        self.assertIn("mode from nix", reason)

    def test_precedence(self):
        common = os.path.join(self.repo, ".git")
        self.set_override({"*": "deny"})
        self.assertIn("override *", self.decide("git commit -m m")[1])
        self.set_override({"*": "deny", common: "ask"})
        decision, reason = self.decide("git commit -m m")
        self.assertEqual(decision, "ask")
        self.assertIn("override for this repository", reason)
        with mock.patch.dict(os.environ, {"AGENT_COMMIT_GATE": "deny"}):
            decision, reason = self.decide("git commit -m m")
        self.assertEqual(decision, "deny")
        self.assertIn("env AGENT_COMMIT_GATE", reason)

    def test_repository_key_matches_from_a_worktree(self):
        self.set_override({os.path.join(self.repo, ".git"): "deny"})
        self.assertEqual(self.decide("git commit -m m", cwd=self.wt)[0], "deny")

    def test_invalid_values_fall_through(self):
        with mock.patch.dict(os.environ, {"AGENT_COMMIT_GATE": "yolo"}):
            decision, reason = self.decide("git commit -m m", mainCheckout="deny")
        self.assertEqual(decision, "deny")
        self.assertIn("ignored AGENT_COMMIT_GATE", reason)
        self.set_override("{not json")
        decision, reason = self.decide("git commit -m m", mainCheckout="deny")
        self.assertEqual(decision, "deny")
        self.assertIn("unreadable override file", reason)
        self.set_override({"*": "allow"})
        decision, reason = self.decide("git commit -m m")
        self.assertEqual(decision, "ask")
        self.assertIn("ignored override *", reason)


class Worktrees(Fixture):
    def test_agent_worktree_is_free_only_when_enabled(self):
        self.assertEqual(gate.agent_worktree(self.wt), "w1")
        self.assertEqual(
            self.decide("git commit -m m", cwd=self.wt, claudeWorktrees="free")[0],
            "allow",
        )
        self.assertEqual(self.decide("git commit -m m", cwd=self.wt)[0], "ask")

    def test_free_does_not_override_a_compound_command(self):
        decision, _ = self.decide(
            "git commit -m m && git push", cwd=self.wt, claudeWorktrees="free"
        )
        self.assertEqual(decision, "ask")

    def test_free_allows_only_a_plain_command(self):
        # An allow covers the whole command text, so anything the shell would
        # expand, redirect or run besides the parsed commit gets the mode.
        for command in (
            "cd . && git commit -qm 'feat: x'",
            # The form Claude Code writes: a trailer with <email> and newlines.
            'git commit -m "chore: Add a.txt\n\nCo-Authored-By: Claude <noreply@anthropic.com>"',
            "git commit -m 'a; b > c $(d) `e`'",
            'git commit -m "quote \\" and (parens) & stuff!"',
        ):
            with self.subTest(command=command):
                decision, _ = self.decide(command, cwd=self.wt, claudeWorktrees="free")
                self.assertEqual(decision, "allow")
        for command in (
            'git commit -m "$(touch pwned)"',
            'git commit -m "`touch pwned`"',
            'git commit -m "\\\\$(touch pwned)"',
            "git commit -m `touch pwned`",
            "git commit -m x > ../../escape",
            "git commit -m x 2>&1",
            "git commit -m 'unterminated",
            "git commit -m x\\;y",
            "git -c core.hooksPath=/dev/null commit -m x",
            "git --exec-path=/tmp commit -m x",
            "GIT_EDITOR=true git commit -m x",
            "nocap git commit -m x",
            "git commit -m x &",
            "git commit -F msg",
            "git commit --no-verify -m x",
            "git commit -m x && git push",
            "git commit -m x && git config user.name y",
            "cd . && cd . && git commit -m x",
            "git commit -m x && cd .",
        ):
            with self.subTest(command=command):
                decision, _ = self.decide(command, cwd=self.wt, claudeWorktrees="free")
                self.assertNotEqual(decision, "allow")

    def test_main_checkout_is_gated(self):
        self.assertIsNone(gate.agent_worktree(self.repo))
        decision, _ = self.decide(
            f"git -C {self.repo} commit -m m", cwd=self.wt, claudeWorktrees="free"
        )
        self.assertEqual(decision, "ask")

    def test_without_marker(self):
        os.remove(os.path.join(self.wt_git_dir, "CLAUDE_BASE"))
        self.assertIsNone(gate.agent_worktree(self.wt))

    def test_other_branch(self):
        sh(self.wt, "git", "switch", "-q", "-c", "mine")
        self.assertIsNone(gate.agent_worktree(self.wt))

    def test_user_made_worktree(self):
        other = os.path.join(os.path.dirname(self.repo), "w2")
        sh(self.repo, "git", "worktree", "add", "-q", "-b", "worktree-w2", other)
        self.assertIsNone(gate.agent_worktree(other))


FAKE_EMACSCLIENT = textwrap.dedent(
    """\
    #!{python}
    # Stands in for emacsclient: answers `--eval t`, and for a review writes
    # the canned result from $FAKE_RESULT into the request directory.
    import json, os, re, sys
    form = sys.argv[-1]
    if os.environ.get("FAKE_EMACS_DOWN"):
        sys.exit(1)
    with open(os.environ["FAKE_LOG"], "a") as log:
        log.write(form + "\\n")
    m = re.match(r'\\(agent-commit-gate-review "(.*)" "(.*)"\\)$', form)
    if m:
        request = m.group(2)
        with open(os.path.join(request, "msg")) as f:
            open(os.environ["FAKE_MSG"], "w").write(f.read())
        result = os.environ.get("FAKE_RESULT")
        if result:
            with open(os.path.join(request, "result.json"), "w") as f:
                f.write(result)
    print("t")
    """
)


class EmacsReview(Fixture):
    def setUp(self):
        super().setUp()
        root = os.path.dirname(self.repo)
        self.client = os.path.join(root, "emacsclient")
        with open(self.client, "w") as f:
            f.write(FAKE_EMACSCLIENT.format(python=sys.executable))
        os.chmod(self.client, 0o755)
        self.log = os.path.join(root, "log")
        self.msg = os.path.join(root, "msg-seen")
        env = mock.patch.dict(os.environ, {"FAKE_LOG": self.log, "FAKE_MSG": self.msg})
        env.start()
        self.addCleanup(env.stop)

    def review(self, command, result=None, **config):
        extra = {"FAKE_RESULT": json.dumps(result)} if result else {}
        with mock.patch.dict(os.environ, extra):
            return self.decide(
                command, mainCheckout="emacs", emacsclient=self.client, **config
            )

    def test_committed(self):
        self.stage(self.repo)
        decision, reason = self.review(
            "git commit -m 'feat: x' -m Body",
            {"status": "committed", "sha": "abc1234", "subject": "feat: y"},
        )
        self.assertEqual(decision, "deny")
        self.assertIn('committed this in Emacs as abc1234 "feat: y"', reason)
        self.assertIn("do not run git commit again", reason)
        with open(self.msg) as f:
            self.assertEqual(f.read(), "feat: x\n\nBody")
        self.assertEqual(os.listdir(os.path.join(self.runtime, "agent-commit-gate")), [])

    def test_not_committed(self):
        self.stage(self.repo)
        decision, reason = self.review(
            "git commit -m m", {"status": "not-committed", "reason": "cancelled by the user"}
        )
        self.assertEqual(decision, "deny")
        self.assertIn("did not commit (cancelled by the user)", reason)

    def test_timeout_cancels(self):
        self.stage(self.repo)
        with mock.patch.object(gate.time, "sleep"), mock.patch.object(
            gate.time, "monotonic", side_effect=[0, 0, 100]
        ):
            decision, reason = self.review("git commit -m m")
        self.assertEqual(decision, "deny")
        self.assertIn("timed out", reason)
        with open(self.log) as f:
            self.assertIn("agent-commit-gate-review-cancel", f.read())

    def test_emacs_down_asks(self):
        self.stage(self.repo)
        with mock.patch.dict(os.environ, {"FAKE_EMACS_DOWN": "1"}):
            decision, reason = self.review("git commit -m m")
        self.assertEqual(decision, "ask")
        self.assertIn("not reachable", reason)

    def test_nothing_staged(self):
        decision, reason = self.review("git commit -m m")
        self.assertEqual(decision, "deny")
        self.assertIn("Nothing is staged", reason)

    def test_unsupported_form_asks(self):
        self.stage(self.repo)
        decision, reason = self.review("git commit --amend -m m")
        self.assertEqual(decision, "ask")
        self.assertIn("`--amend`", reason)

    def test_elisp_string_escaping(self):
        self.assertEqual(gate.elisp_string('a"b\\c'), '"a\\"b\\\\c"')


if __name__ == "__main__":
    unittest.main()
