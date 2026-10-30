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
  # opening it headlessly when no buffer holds it yet, and its diagnostics are
  # read from Flycheck, Flymake and lsp-mode alike. See format-on-edit.el.
  #
  # Emacs never blocks on this: `emacsclient --eval` only queues a job and
  # returns, Emacs works through timers and server callbacks, and this script
  # polls for the job's done marker. See docs/adr/0009-async-format-on-edit.md.
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
      # The done marker is separate because the report is optional: a clean
      # file in a non-manifest gets none.
      out=$(mktemp -d)
      trap 'rm -rf "$out"' EXIT
      report="$out/report"
      done_marker="$out/done"

      # Queueing returns at once; a stuck daemon costs at most this timeout.
      timeout 5 "$emacsclient" --eval \
        "(progn (load \"${./format-on-edit.el}\" nil t)
                (claude-format-on-edit $elisp_file \"$report\" \"$done_marker\"))" \
        >/dev/null 2>&1 || exit 0

      # Emacs gives up on its own after 22 s (claude-format-on-edit-job-deadline)
      # and still writes the marker. This deadline only covers a daemon that
      # died mid-job, and leaves the queueing step room under the hook's 30 s
      # timeout.
      deadline=$((SECONDS + 24))
      while [ ! -e "$done_marker" ] && [ "$SECONDS" -lt "$deadline" ]; do
        sleep 0.1
      done

      # Without the marker the report may be half written.
      [ -e "$done_marker" ] && [ -s "$report" ] || exit 0
      jq -n --rawfile context "$report" \
        '{hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $context
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
