# Regression test for dot-emacs-038: sops.el must not hang on save.
#
#   nix build .#test-emacs-sops-save -L
#
# Upstream's `sops--run' waits for the sops subprocess with
# `(accept-process-output PROC 0.1)' and leaves the loop only when the process
# sentinel sets a flag.  `sops-mode' also enables `auto-revert-mode', which
# installs a file-notify watch; while such a watch is live Emacs does not run
# sentinels when waiting on a *specific* process, so the flag never flips and
# Emacs spins forever on save.  common/emacs-sops-fix-overlay.nix rewrites the
# wait to `(accept-process-output nil 0.1)'.
#
# The test encrypts a fixture with a throwaway age key generated inside the
# build, opens it in batch Emacs, edits, saves under a timeout, and checks the
# edit survives a round-trip through sops.  It asserts a file-notify watch is
# actually present -- without one the test would pass even unpatched.
#
# Deliberately a package rather than a check: it builds Emacs' closure, which
# does not belong in the `nix flake check' loop.
{
  runCommand,
  emacs,
  emacsPackages,
  sops,
  age,
  coreutils,
}:

let
  testEl = ''
    ;;; -*- lexical-binding: t; -*-
    (add-to-list 'load-path (getenv "SOPS_EL_DIR"))
    (require 'sops)
    (global-sops-mode 1)
    (let ((f (expand-file-name "secrets.yaml" default-directory))
          (failures nil))
      (find-file f)
      (unless sops-mode
        (push "sops-mode did not enable (decrypt on find-file failed)" failures))
      (unless (bound-and-true-p auto-revert-notify-watch-descriptor)
        (push "no file-notify watch: the test would not exercise the bug" failures))
      (goto-char (point-max))
      (insert "\nprobe: saved-by-emacs\n")
      (save-buffer)
      (let ((r (sops--run (list "decrypt" f))))
        (unless (eq 0 (plist-get r :exit-status))
          (push (format "round-trip decrypt failed: %s" (plist-get r :stderr)) failures))
        (unless (string-match-p "saved-by-emacs" (plist-get r :stdout))
          (push "the edit did not survive the save" failures)))
      (if failures
          (progn (dolist (m failures) (message "FAIL: %s" m)) (kill-emacs 1))
        (message "PASS: sops save completed and round-tripped")))
  '';
in
runCommand "test-emacs-sops-save"
  {
    nativeBuildInputs = [
      emacs
      sops
      age
      coreutils
    ];
  }
  ''
    export SOPS_EL_DIR=$(echo ${emacsPackages.sops}/share/emacs/site-lisp/elpa/sops-*)
    export HOME="$PWD/home"
    mkdir -p "$HOME"

    # Throwaway identity; never leaves the build sandbox.
    age-keygen -o "$HOME/key.txt" 2>/dev/null
    recipient=$(age-keygen -y "$HOME/key.txt")
    export SOPS_AGE_KEY_FILE="$HOME/key.txt"

    mkdir -p work && cd work
    cat > .sops.yaml <<EOF
    creation_rules:
        - path_regex: secrets\.yaml$
          age: $recipient
    EOF
    printf 'answer: 42\n' > secrets.yaml
    sops encrypt -i secrets.yaml
    grep -q ENC secrets.yaml || { echo "fixture is not encrypted"; exit 1; }

    cp ${builtins.toFile "sops-save-test.el" testEl} test.el

    # The bug is an infinite busy loop, so the timeout is the assertion.
    if ! timeout 120 emacs -Q --batch -l ./test.el; then
      echo "sops save hung or failed (see messages above)"
      exit 1
    fi

    touch "$out"
  ''
