# The ERT suite of workstation/emacs/packages/walkthrough.el.
#
#   nix build .#test-walkthrough -L
#
# Run it after any change to walkthrough.el or walkthrough-test.el.  The
# suite guards what Nix evaluation cannot see: the hunk-coverage rule a draft
# walkthrough is validated against, the step buffer Magit builds from the two
# commits, the finding marks written back to the file, and the comment label
# that lost its range when Magit renamed `magit-buffer-range'.
#
# The tests build a throwaway repository with git, so the build needs git but
# no network and no agent.
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
  # magit brings its own dependencies onto the load path; markdown-mode is
  # what renders explanations, and the suite checks the rendering.
  emacsWithPackages = (emacsPackagesFor emacs).emacsWithPackages (epkgs: [
    epkgs.magit
    epkgs.markdown-mode
  ]);
in
runCommand "test-walkthrough"
  {
    nativeBuildInputs = [
      emacsWithPackages
      git
      coreutils
    ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"

    # git refuses to guess, and the fixture's commits would warn on every run.
    git config --global init.defaultBranch main
    git config --global user.email "test@example.com"
    git config --global user.name "Test"

    mkdir -p package
    cp ${../workstation/emacs/packages/walkthrough.el} package/walkthrough.el
    cp ${../workstation/emacs/packages/walkthrough-test.el} package/walkthrough-test.el
    cd package

    if ! emacs -batch -L . -l walkthrough-test.el -f ert-run-tests-batch-and-exit; then
      echo "walkthrough ERT suite failed (see the report above)"
      exit 1
    fi

    touch "$out"
  ''
