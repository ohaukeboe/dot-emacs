{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.commitGate;

  # Decides every `git commit` the agent runs: the staging guard, free
  # commits in the agent's own worktrees, and the ask/emacs/deny mode. Run by
  # the rewriter chain rather than as a hook of its own, because an allow
  # only works when the chain also rewrites the command text (the static ask
  # rule is matched against the rewritten text). See commit-gate.py and
  # docs/adr/0006-agent-commit-gate.md.
  gate = pkgs.writers.writePython3Bin "agent-commit-gate" {
    flakeIgnore = [
      # Conflicts with the formatter (ruff), which owns layout.
      "E203"
      "E501"
      "W503"
    ];
  } (builtins.readFile ./commit-gate.py);

  configFile = pkgs.writeText "agent-commit-gate.json" (
    builtins.toJSON {
      inherit (cfg) mainCheckout claudeWorktrees emacsTimeout;
      emacsclient = "${config.programs.emacs.finalPackage}/bin/emacsclient";
    }
  );

  # Written by Emacs (agent-commit-gate-set), read by the gate. Fixed rather
  # than an option: Emacs computes the same path from XDG_STATE_HOME.
  overridePath = "${config.xdg.stateHome}/agent-commit-gate/override.json";
in
{
  options.agents.commitGate = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Decide the agent's `git commit` calls in the rewriter chain: deny a
        commit that stages in the same call, and apply the mode below.
      '';
    };

    mainCheckout = lib.mkOption {
      type = lib.types.enum [
        "ask"
        "emacs"
        "deny"
      ];
      default = "ask";
      description = ''
        Default handling of a commit outside the agent's own worktrees:
        "ask" prompts, "emacs" opens the commit for review in Magit and lets
        Emacs make it, "deny" refuses. AGENT_COMMIT_GATE at launch, or the
        override file set with `M-x agent-commit-gate-set`, takes precedence.
      '';
    };

    claudeWorktrees = lib.mkOption {
      type = lib.types.enum [
        "gated"
        "free"
      ];
      default = "gated";
      description = ''
        "free" lets the agent commit without asking in a worktree Claude
        Code created (.claude/worktrees/<name> on branch worktree-<name>).
        Any other checkout keeps the mainCheckout mode.
      '';
    };

    emacsTimeout = lib.mkOption {
      type = lib.types.ints.between 30 3000;
      default = 1200;
      description = ''
        Seconds the gate waits for an Emacs review before cancelling it. The
        chain's hook timeout is set 60 seconds above it, so the gate always
        gets to withdraw the review itself.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = gate;
      description = "The gate executable the rewriter chain calls.";
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = configFile;
      description = "The gate's settings, passed as AGENT_COMMIT_GATE_CONFIG.";
    };
  };

  config = lib.mkIf cfg.enable {
    agents.tools.commit-gate.packages = [ gate ];

    # The agent must not choose its own mode. Sandboxed Bash cannot write
    # $HOME, but the Edit and Write tools run outside the sandbox. `//` makes
    # the rule path absolute.
    programs.claude-code.settings.permissions.deny = [
      "Edit(/${overridePath})"
      "Write(/${overridePath})"
    ];

    assertions = [
      {
        assertion = lib.elem "git commit" config.agents.sensitiveBashPrefixes;
        message = ''
          agents.commitGate is enabled but "git commit" is missing from
          agents.sensitiveBashPrefixes. The static ask rule is the fail-safe
          when the rewriter chain is killed before it decides; restore the entry
          in workstation/agents/default.nix.
        '';
      }
      {
        assertion = config.agents.bashRewriters != { };
        message = ''
          agents.commitGate is enabled but no agents.bashRewriters stage is
          registered, so the rewriter chain hook that runs the gate is not
          rendered. Enable rtk or the process cap, or disable
          agents.commitGate in workstation/agents/commit-gate.nix.
        '';
      }
    ];
  };
}
