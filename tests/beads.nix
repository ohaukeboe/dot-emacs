# The ERT suite of workstation/emacs/packages/beads.el.
#
#   nix build .#test-beads -L
#
# Run it after any change to beads.el or beads-test.el.  The suite guards two
# things Nix evaluation cannot see: the structural invariant of the Magit
# section tree (dot-emacs-l3y, a refresh whose insertion point was moved came
# back with sections whose end preceded their start), and the relation marks
# and navigation added for dot-emacs-9ym.
#
# The tests supply their own `bd' -- a shell script on PATH that cats fixture
# files -- so the build needs neither the real tracker nor a database.  They do
# need git, because the fixture builds a throwaway repository for Magit to show.
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
  # magit brings its own dependencies (transient, compat, dash, with-editor,
  # llama, seq) onto the load path, so the suite only has to name magit.
  emacsWithMagit = (emacsPackagesFor emacs).emacsWithPackages (epkgs: [ epkgs.magit ]);
in
runCommand "test-beads"
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

    # git refuses to guess, and the fixture's commits would warn on every run.
    git config --global init.defaultBranch main
    git config --global user.email "test@example.com"
    git config --global user.name "Test"

    mkdir -p package
    cp ${../workstation/emacs/packages/beads.el} package/beads.el
    cp ${../workstation/emacs/packages/beads-test.el} package/beads-test.el
    cd package

    if ! emacs -batch -L . -l beads-test.el -f ert-run-tests-batch-and-exit; then
      echo "beads ERT suite failed (see the report above)"
      exit 1
    fi

    touch "$out"
  ''
