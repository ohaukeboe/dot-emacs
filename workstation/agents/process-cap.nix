{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.processCap;

  # With memory-cap.nix enabled, a command also lands in the agent slice with
  # its own memory limit, so a runaway build is OOM-killed on its own.
  memoryScopeArgs = lib.optionals config.agents.memoryCap.enable config.agents.memoryCap.commandScopeArgs;

  # Runtime cap for agent-spawned shell commands.
  #
  # Processes started by a Bash tool call outlive their session: Claude Code's
  # own Bash timeout moves a slow command to a background task rather than
  # killing it, so a hang survives until the next reboot. Three such orphans
  # were found on work-laptop burning two cores for five days (dot-emacs-k6c).
  #
  # The limit is enforced by the user's systemd manager, not by the launching
  # process, because the launcher is exactly what disappears in that failure
  # mode. A `timeout 25` style wrapper — as format-on-edit.nix uses for a single
  # known call — cannot do this: it is itself part of the tree that dies.
  #
  # Kills are auditable afterwards: the scope description carries the tag, the
  # allowance and the command text, so `journalctl --user -g claude-cap` answers
  # both "what was killed" and "is the cap too tight".
  helper = pkgs.writeShellApplication {
    name = "agent-process-cap";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      usage() {
        echo "agent-process-cap: $1" >&2
        echo "usage: agent-process-cap run <fg|bg> <base64-command>" >&2
        exit 64
      }

      [ "$#" -eq 3 ] || usage "expected 3 arguments, got $#"
      [ "$1" = "run" ] || usage "unknown subcommand: $1"

      case "$2" in
        fg) cap=${toString cfg.foregroundSeconds} ;;
        bg) cap=${toString cfg.backgroundSeconds} ;;
        *) usage "unknown mode: $2" ;;
      esac
      mode=$2

      command=$(printf '%s' "$3" | base64 -d 2>/dev/null) || usage "payload is not base64"
      [ -n "$command" ] || usage "payload decoded to an empty command"

      # Fail open. A hook that breaks every Bash call is a worse outage than the
      # leak it prevents, so anything unexpected runs the command uncapped.
      bus=''${DBUS_SESSION_BUS_ADDRESS:-}
      runtime=''${XDG_RUNTIME_DIR:-}
      if ! command -v systemd-run >/dev/null 2>&1 ||
        { [ -z "$bus" ] && [ ! -S "$runtime/bus" ]; }; then
        exec bash -c "$command"
      fi

      # A `cd` inside the command moves the scope's shell, not the caller's —
      # a child process cannot change its parent's directory, so nothing here
      # can propagate it back. That costs nothing with this harness: it
      # captures the directory with its own `pwd -P` appended outside this
      # wrapper and then resets it to the project root on every call, and it
      # does not carry environment variables between calls either. Should a
      # harness version start persisting the directory, the stage would have to
      # emit a compound command that restores it in the caller's own shell.

      # bash announces a signal death of its own child on its stderr
      # ("Terminated  systemd-run --user --scope ..."). That notice would land
      # inside the command's captured stderr, so the real stderr is held on fd 3
      # and only the command's own output is passed to it.
      exec 3>&2
      exec 2>/dev/null

      # The command text is handed to the inner shell exactly as written, which
      # is what `bash -c` does uncapped. Nothing may be appended to it: a
      # trailing heredoc would read the appended line as part of its body, and
      # a trailing comment would eat it entirely.
      set +e
      SECONDS=0
      systemd-run --user --scope -q --collect --expand-environment=no \
        --description="claude-cap $mode ''${cap}s: $command" \
        -p RuntimeMaxSec="$cap" \
        -p TimeoutStopSec=${toString cfg.graceSeconds} \
        ${lib.escapeShellArgs memoryScopeArgs} \
        -- bash -c "$command" 2>&3
      rc=$?
      set -e

      exec 2>&3

      # 143 is SIGTERM at the cap, 137 SIGKILL after the grace period. Either
      # way the agent must be told why its command died, or a capped hang looks
      # like an unexplained failure. A memory-limit kill exits the same way —
      # systemd stops the whole scope once the kernel OOM-kills a process in it —
      # so the elapsed time tells the two apart.
      case "$rc" in
        143 | 137)
          if [ "$SECONDS" -ge "$cap" ]; then
            echo "[process-cap] terminated after the $mode runtime cap of ''${cap}s" >&2
          elif ${lib.boolToString config.agents.memoryCap.enable}; then
            echo "[process-cap] killed after ''${SECONDS}s, before the runtime cap; most likely the memory limit (journalctl --user -g 'OOM killer' --since -5m)" >&2
          fi
          ;;
      esac

      exit "$rc"
    '';
  };

  # Rewriter stage. Wraps whatever command text survived the earlier stages,
  # and is the last stage by assertion — anything after it would rewrite text
  # that is already inside the base64 payload.
  #
  # The command travels as base64 because Claude Code embeds the final text in
  # `eval '<command>'`: a single quote introduced here would break the call, and
  # escaping one in place is the class of bug that corrupts one command in a
  # hundred. base64 output is alphanumeric plus +/= and needs no escaping.
  stage = pkgs.writeShellApplication {
    name = "agent-process-cap-stage";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      helper=${lib.getExe helper}
      token=${lib.escapeShellArg cfg.optOutToken}

      payload=$(cat)
      # A malformed payload must not fail the hook, only skip it.
      command=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null || true)
      [ -n "$command" ] || exit 0

      # Never wrap a wrapper.
      case "$command" in
        "$helper run "*) exit 0 ;;
      esac

      # The explicit opt-out. A command marked with the leading token runs
      # uncapped, with the token stripped so it never reaches the shell. There
      # is deliberately no flag on the helper for this: one way to opt out.
      case "$command" in
        "$token "*)
          jq -n --argjson input "$(jq -c '.tool_input' <<<"$payload")" \
            --arg command "''${command#"$token" }" \
            '{hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecisionReason: "process-cap: opted out with the leading token",
                updatedInput: ($input + {command: $command})
              }}'
          exit 0
          ;;
      esac

      # Deliberately detached work is expected to run longer than a foreground
      # command, so it gets its own allowance.
      background=$(jq -r '.tool_input.run_in_background // false' <<<"$payload" 2>/dev/null || echo false)
      if [ "$background" = "true" ]; then mode="bg"; else mode="fg"; fi

      encoded=$(printf '%s' "$command" | base64 -w0)

      jq -n --argjson input "$(jq -c '.tool_input' <<<"$payload")" \
        --arg command "$helper run $mode $encoded" \
        --arg mode "$mode" \
        '{hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecisionReason: ("process-cap: " + $mode + " runtime cap"),
            updatedInput: ($input + {command: $command})
          }}'
    '';
  };
in
{
  options.agents.processCap = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Cap the runtime of every shell command an agent runs, so a hang is
        killed by systemd instead of living until the next reboot.
      '';
    };

    foregroundSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3600;
      description = ''
        Runtime allowance for a foreground command. The target is a process
        that lives for days, not a slow build, so this sits well above the
        slowest legitimate command rather than close to it.
      '';
    };

    backgroundSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14400;
      description = "Runtime allowance for a command the agent runs in the background.";
    };

    graceSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = ''
        Time between the graceful stop request at the allowance and the
        unconditional kill, so a command can release locks and remove partial
        output before it goes.
      '';
    };

    optOutToken = lib.mkOption {
      type = lib.types.strMatching "[a-z][a-z0-9-]*";
      default = "nocap";
      description = ''
        Leading token that exempts a single command from the cap. Stripped
        before the command runs.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.foregroundSeconds >= 60;
        message = ''
          agents.processCap.foregroundSeconds is ${toString cfg.foregroundSeconds}s, under a
          minute, which kills ordinary work. Raise it in workstation/agents/process-cap.nix
          (or on the machine that set it) to at least 60.
        '';
      }
      {
        assertion = cfg.backgroundSeconds >= cfg.foregroundSeconds;
        message = ''
          agents.processCap.backgroundSeconds (${toString cfg.backgroundSeconds}s) is below
          foregroundSeconds (${toString cfg.foregroundSeconds}s). Background work exists to run
          longer, so this ordering is always a typo. Fix it in
          workstation/agents/process-cap.nix.
        '';
      }
      {
        assertion = cfg.graceSeconds < cfg.foregroundSeconds;
        message = ''
          agents.processCap.graceSeconds (${toString cfg.graceSeconds}s) is at or above
          foregroundSeconds (${toString cfg.foregroundSeconds}s), which doubles the effective
          cap. Lower it in workstation/agents/process-cap.nix.
        '';
      }
    ];

    # Order 90: after every rewriter that changes the command text, and asserted
    # to be the last stage in workstation/agents/default.nix.
    agents.bashRewriters.processCap = {
      order = 90;
      executable = stage;
    };

    agents.tools.process-cap = {
      packages = [ helper ];
      docs.both = [ ./process-cap-docs.md ];
    };
  };
}
