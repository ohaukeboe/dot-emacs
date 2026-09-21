# Overlay: fix sops.el hanging forever on save.
#
# `sops--run' starts the sops subprocess with `make-process' and then waits in
#
#     (while (not done) (accept-process-output proc 0.1))
#
# where `done' is set only by the process sentinel.  `sops-mode' also enables
# `auto-revert-mode', which installs a file-notify (inotify) watch on the
# buffer's file.  While such a watch descriptor is live, Emacs does not run
# process sentinels from `wait_reading_process_output' when it is waiting on a
# *specific* process, so `done' never becomes non-nil: sops exits, its output is
# captured, and Emacs spins at 100% CPU forever.  Decryption on `find-file'
# works because it runs before the watch is installed.
#
# Waiting on any process (nil) lets the sentinel run.  Verified against
# emacs -Q --batch and an emacs --daemon: save completes in ~0.1s with the
# file-notify watch still active, and the ciphertext round-trips.
#
# Upstream: https://github.com/djgoku/sops — drop this overlay once fixed there.
final: prev: {
  emacsPackagesFor =
    emacs:
    (prev.emacsPackagesFor emacs).overrideScope (
      _efinal: eprev: {
        sops = eprev.sops.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace sops.el \
              --replace-fail "(accept-process-output proc 0.1)" "(accept-process-output nil 0.1)"
          '';
        });
      }
    );
}
