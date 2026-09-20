# Emacs configuration tests
# ERT suites run in batch against the Emacs on PATH; no package.el download,
# every dependency comes from the Nix-built Emacs.

# Run every Emacs test suite
test-emacs: test-beads test-config

# Section invariants of the beads section in Magit status buffers
test-beads:
    cd workstation/emacs/packages && emacs -batch -L . -l beads-test.el -f ert-run-tests-batch-and-exit

# Pieces of config.org whose breakage is silent
test-config:
    cd workstation/emacs && emacs -batch -l config-test.el -f ert-run-tests-batch-and-exit
