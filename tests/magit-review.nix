# The ERT suite of workstation/emacs/packages/magit-review.el.
#
#   nix build .#test-magit-review -L
#
# Run it after any change to magit-review.el or magit-review-test.el, and
# after bumping Magit: the package reads Magit's hunk sections and
# buffer-local variables, which Magit has renamed without aliases before.
# The suite drives the review commands in real Magit buffers and checks the
# prompt handed to a capturing send function, the comments drawn in the
# buffers and the pending, sent and discarded comments.
#
# The tests build a throwaway repository with git, so the build needs git but
# no network and no agent.  walkthrough.el is copied in for the cases that
# hand off accepted findings and replies.
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
  # what walkthrough renders explanations with and what lists the review.
  emacsWithPackages = (emacsPackagesFor emacs).emacsWithPackages (epkgs: [
    epkgs.magit
    epkgs.markdown-mode
  ]);
in
runCommand "test-magit-review"
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
    cp ${../workstation/emacs/packages/magit-review.el} package/magit-review.el
    cp ${../workstation/emacs/packages/magit-review-test.el} package/magit-review-test.el
    cp ${../workstation/emacs/packages/walkthrough.el} package/walkthrough.el
    cd package

    if ! emacs -batch -L . -l magit-review-test.el -f ert-run-tests-batch-and-exit; then
      echo "magit-review ERT suite failed (see the report above)"
      exit 1
    fi

    touch "$out"
  ''
