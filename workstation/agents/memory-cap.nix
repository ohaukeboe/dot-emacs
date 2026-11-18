{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.memoryCap;

  # Memory containment for coding agents.
  #
  # Every `claude` started from Emacs used to share Emacs's own cgroup
  # (app-cosmic-emacs-<pid>.scope). An OOM kill works on whole cgroups, so one
  # runaway session took Emacs and every other session down with it.
  #
  # Each session now gets its own scope under one user slice with a hard
  # ceiling. When agents run out of memory, the kernel's OOM killer fires inside
  # that slice, on its largest process, before the rest of the desktop is under
  # pressure. This needs no OOM daemon.
  #
  # The slice ceiling is the only limit. Scopes carry none, and nothing sets
  # MemoryHigh: inside the sandbox every Bash command shares its session's
  # scope, so a per-session MemoryHigh throttled `nix flake check` to a crawl
  # without protecting Emacs any better (dot-emacs-584).
  #
  # Limits are percentages: systemd resolves them against physical RAM (swap
  # size for MemorySwapMax), so one setting fits both 32 GB and 64 GB machines.
  slice = "agents.slice";

  # Runs one Claude Code session in its own scope. The scope keeps the caller's
  # terminal, environment and PID (`systemd-run --scope` execs the command in
  # place), so Emacs and the terminal backend see no difference.
  launcher = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      real=${lib.getExe cfg.package}

      # Fail open, like process-cap: without a user manager the session runs
      # uncapped rather than not at all.
      bus=''${DBUS_SESSION_BUS_ADDRESS:-}
      runtime=''${XDG_RUNTIME_DIR:-}
      if { [ -z "$bus" ] && [ ! -S "$runtime/bus" ]; }; then
        exec "$real" "$@"
      fi

      exec systemd-run --user --scope -q --collect \
        --slice=${slice} \
        --unit="claude-$$" \
        --description="Claude Code session in $PWD" \
        -- "$real" "$@"
    '';
  };

  # Keep name and version: the home-manager module gates behaviour on
  # `lib.getVersion programs.claude-code.package`.
  wrapped = pkgs.symlinkJoin {
    name = "claude-code-${cfg.package.version}";
    inherit (cfg.package) version;
    paths = [ cfg.package ];
    postBuild = ''
      rm "$out/bin/claude"
      ln -s ${lib.getExe launcher} "$out/bin/claude"
    '';
    meta = cfg.package.meta // {
      mainProgram = "claude";
    };
  };
in
{
  options.agents.memoryCap = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      description = ''
        Run coding agents in their own memory-limited systemd slice, so an
        agent that runs out of memory is OOM-killed on its own instead of
        taking Emacs and the other sessions with it.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.claude-code;
      description = "Claude Code package to wrap.";
    };

    slice = {
      max = lib.mkOption {
        type = lib.types.str;
        default = "60%";
        description = ''
          MemoryMax for all agents together (sessions and their Bash
          commands). Above it the kernel OOM-kills inside the slice.
        '';
      };
      swapMax = lib.mkOption {
        type = lib.types.str;
        default = "25%";
        description = ''
          MemorySwapMax for all agents together, relative to swap size.
          Without it a leak fills swap (sized for hibernation) before the
          memory limit triggers an OOM kill, and the whole desktop stalls on
          swap I/O meanwhile.
        '';
      };
    };

    commandScopeArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = [ "--slice=${slice}" ];
      description = "Extra systemd-run arguments that put a Bash tool command in the agent slice.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.slices.agents = {
      Unit.Description = "Coding agents (memory-limited)";
      Slice = {
        MemoryMax = cfg.slice.max;
        MemorySwapMax = cfg.slice.swapMax;
      };
    };

    programs.claude-code.package = wrapped;

    agents.tools.memory-cap.docs.both = [ ./memory-cap-docs.md ];
  };
}
