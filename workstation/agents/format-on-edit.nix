{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Formatting after every edit has to be deterministic, so it lives in a hook
  # rather than in agents-global.md: prose in a memory file is advisory and
  # decays as a session grows, a PostToolUse hook fires on every match.
  #
  # The file is formatted through whatever language server Emacs has for it,
  # opening it headlessly when no buffer holds it yet. Anything that could make
  # Emacs wait for a human (project-root import, file-watcher confirmation) is
  # stubbed to "no" for the duration, since a blocked `emacsclient --eval` would
  # stall the agent until the timeout.
  #
  # Diagnostics are reported through `hookSpecificOutput.additionalContext`,
  # which reaches Claude on exit 0. Exit 2 would also surface them, but as a
  # warning on every lint hit, which turns routine editing into interruptions.
  formatOnEdit = pkgs.writeShellApplication {
    name = "claude-format-on-edit";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      emacsclient="${config.programs.emacs.finalPackage}/bin/emacsclient"

      # Opening an unopened file costs a major mode and possibly a language
      # server, so keep the hook off files no formatter is meant to touch.
      max_bytes=2000000

      payload=$(cat)
      # A malformed payload must not fail the hook, only skip it.
      file=$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null || true)
      [ -n "$file" ] || exit 0
      [ -f "$file" ] || exit 0
      case "$file" in
        */.git/* | */node_modules/* | */result/* | /nix/store/*) exit 0 ;;
      esac
      [ "$(stat -c %s "$file")" -le "$max_bytes" ] || exit 0
      # Outside a repository there is no project to attach a language server
      # to. lsp-mode would happily guess a root like /tmp and leave a server
      # running there, so scratch files are left alone.
      git -C "$(dirname "$file")" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

      # JSON string escaping is close enough to Elisp string escaping for paths.
      elisp_file=$(jq -r '.tool_input.file_path | @json' <<<"$payload" 2>/dev/null || true)
      [ -n "$elisp_file" ] || exit 0

      # Fails fast when no daemon or frame is listening.
      "$emacsclient" --eval t >/dev/null 2>&1 || exit 0

      # Elisp reports through a temp file: `emacsclient --eval` prints the
      # return value as an escaped Elisp literal, which would need unquoting.
      report=$(mktemp)
      trap 'rm -f "$report"' EXIT

      timeout 25 "$emacsclient" --eval "
        (progn
          (require 'cl-lib)
          (let* ((report \"$report\")
                 (existing (get-file-buffer $elisp_file))
                 ;; NOWARN: a file that changed on disk must not raise a prompt.
                 (buf (or existing
                          (ignore-errors (find-file-noselect $elisp_file t)))))
            (when (and buf (not (buffer-modified-p buf)))
              (unwind-protect
                  (with-current-buffer buf
                    ;; Nothing below may wait for a human. Anything that asks
                    ;; gets a 'no' and carries on.
                    (cl-letf (((symbol-function 'y-or-n-p) #'ignore)
                              ((symbol-function 'yes-or-no-p) #'ignore))
                      (when existing
                        (revert-buffer :ignore-auto :noconfirm :preserve-modes))
                      (unless (bound-and-true-p lsp-mode)
                        (let ((lsp-auto-guess-root t)
                              (lsp-restart 'ignore)
                              (lsp-enable-file-watchers nil))
                          ;; No client for this mode simply signals; that is a
                          ;; valid outcome, the diagnostics pass still runs.
                          (ignore-errors (lsp))))
                      ;; A workspace that is up but still negotiating reports
                      ;; no capabilities yet, so wait for the formatting one.
                      ;; A cold server has no workspace attached yet and is not
                      ;; worth waiting for: it will be warm by the next edit.
                      (let ((deadline (+ (float-time) 3.0)))
                        (while (and (bound-and-true-p lsp-mode)
                                    (ignore-errors (lsp-workspaces))
                                    (not (ignore-errors
                                           (lsp-feature? \"textDocument/formatting\")))
                                    (< (float-time) deadline))
                          (sit-for 0.1)))
                      (when (and (bound-and-true-p lsp-mode)
                                 (fboundp 'lsp-feature?)
                                 (ignore-errors
                                   (lsp-feature? \"textDocument/formatting\")))
                        ;; A formatter refuses to touch a syntactically broken
                        ;; file and lsp-format-buffer signals. That is exactly
                        ;; when the diagnostics below matter, so it must not
                        ;; abort the rest.
                        (ignore-errors
                          (lsp-format-buffer)
                          (save-buffer)))
                      (when (bound-and-true-p flycheck-mode)
                        (ignore-errors (flycheck-buffer))
                        (let ((deadline (+ (float-time) 6.0)))
                          (while (and (memq flycheck-last-status-change
                                            '(running not-checked))
                                      (< (float-time) deadline))
                            (sit-for 0.1)))
                        (let ((lines
                               (delq nil
                                     (mapcar
                                      (lambda (e)
                                        (when (memq (flycheck-error-level e)
                                                    '(error warning))
                                          (format \"%s:%s: %s: %s\"
                                                  (file-name-nondirectory
                                                   (buffer-file-name))
                                                  (or (flycheck-error-line e) 0)
                                                  (flycheck-error-level e)
                                                  (flycheck-error-message e))))
                                      flycheck-current-errors))))
                          (when lines
                            (with-temp-file report
                              (insert (mapconcat #'identity
                                                 (seq-take lines 20)
                                                 \"\n\"))))))))
                ;; Leave the user's Emacs as it was found: no buffer, and no
                ;; language server that only this hook was using.
                (unless existing
                  (when (buffer-live-p buf)
                    (kill-buffer buf))
                  ;; Covers servers this hook started, including ones still
                  ;; initializing, which are not attached to the buffer yet.
                  (ignore-errors
                    (dolist (w (lsp--session-workspaces (lsp-session)))
                      (when (null (seq-filter #'buffer-live-p
                                              (lsp--workspace-buffers w)))
                        (lsp-workspace-shutdown w)))))))))" >/dev/null 2>&1 || true

      [ -s "$report" ] || exit 0
      jq -n --rawfile diagnostics "$report" \
        '{hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: ("Diagnostics for the file just edited:\n" + $diagnostics)
          }}'
    '';
  };
in
{
  agents.tools.format-on-edit = {
    enable = lib.mkDefault pkgs.stdenv.hostPlatform.isLinux;
    hooks.PostToolUse = [
      {
        matcher = "Edit|Write";
        hooks = [
          {
            type = "command";
            command = lib.getExe formatOnEdit;
            timeout = 30;
            statusMessage = "Formatting edited file...";
          }
        ];
      }
    ];
  };
}
