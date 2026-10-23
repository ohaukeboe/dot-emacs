# Unit tests for workstation/agents/commit-gate.py, run by `nix flake check`.
#
# The staging guard, target resolution, message extraction, mode precedence,
# agent-worktree detection, and the gate's side of the Emacs review against
# a fake emacsclient. Fixtures are throwaway git repositories made inside the
# build, so the check needs only python3 and git and stays fast.
{
  runCommand,
  python3,
  git,
}:

runCommand "agent-commit-gate-test"
  {
    nativeBuildInputs = [
      python3
      git
    ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    git config --global init.defaultBranch main
    git config --global user.email "test@example.com"
    git config --global user.name "Test"

    cp ${../workstation/agents/commit-gate.py} commit_gate.py
    cp ${./agent-commit-gate_test.py} agent_commit_gate_test.py
    python3 -m unittest -v agent_commit_gate_test
    touch "$out"
  ''
