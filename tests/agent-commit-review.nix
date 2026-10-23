# The ERT suite of workstation/emacs/packages/agent-commit-gate.el: the
# Emacs side of the agent commit gate.
#
#   nix build .#test-agent-commit-review -L
#
# Run it after any change to agent-commit-gate.el.  The tests open real Magit
# commit buffers in a throwaway repository, finish or cancel them, and check
# the result file the gate waits for -- including that a review whose gate has
# gone away refuses to commit.
#
# Deliberately a package rather than a check: it builds an Emacs closure, and
# `nix flake check` runs before every commit.
{
  runCommand,
  emacs,
  emacsPackagesFor,
  git,
  coreutils,
}:

let
  emacsWithMagit = (emacsPackagesFor emacs).emacsWithPackages (epkgs: [ epkgs.magit ]);
in
runCommand "test-agent-commit-review"
  {
    nativeBuildInputs = [
      emacsWithMagit
      git
      coreutils
    ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    git config --global init.defaultBranch main
    git config --global user.email "test@example.com"
    git config --global user.name "Test"

    mkdir -p package
    cp ${../workstation/emacs/packages/agent-commit-gate.el} package/agent-commit-gate.el
    cp ${../workstation/emacs/packages/agent-commit-gate-test.el} package/agent-commit-gate-test.el
    cd package

    if ! timeout 300 emacs -batch -L . -l agent-commit-gate-test.el -f ert-run-tests-batch-and-exit; then
      echo "agent-commit-gate ERT suite failed (see the report above)"
      exit 1
    fi

    touch "$out"
  ''
