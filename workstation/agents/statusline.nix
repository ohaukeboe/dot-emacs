{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.context;

  contextStatusline = pkgs.callPackage ./packages/context-statusline.nix {
    inherit (cfg) warnTokens strongTokens;
    cavemanScript =
      if config.agents.tools.caveman.enable then
        "${inputs.caveman}/src/hooks/caveman-statusline.sh"
      else
        null;
  };
in
{
  options.agents.context = {
    statusLine.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the Claude Code status line shows the context size next to the
        caveman badge. Replaces caveman's own status line.
      '';
    };
    warnTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 200000;
      description = "Context size above which the status line turns yellow.";
    };
    strongTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 400000;
      description = "Context size above which the status line turns bold red.";
    };
    autoCompactTokens = lib.mkOption {
      type = lib.types.ints.between 100000 1000000;
      default = 400000;
      description = ''
        Context size at which Claude Code summarizes the conversation, or the
        model's window if that is smaller.
      '';
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.warnTokens < cfg.strongTokens;
          message = ''
            agents.context.warnTokens (${toString cfg.warnTokens}) is not below strongTokens
            (${toString cfg.strongTokens}), so the yellow warning would never show. Lower
            warnTokens or raise strongTokens in workstation/agents/statusline.nix (or on the
            machine that set it).
          '';
        }
        {
          assertion = cfg.autoCompactTokens >= cfg.strongTokens;
          message = ''
            agents.context.autoCompactTokens (${toString cfg.autoCompactTokens}) is below
            strongTokens (${toString cfg.strongTokens}), so the context is summarized before
            the strong warning can show. Raise autoCompactTokens or lower strongTokens in
            workstation/agents/statusline.nix.
          '';
        }
      ];

      # A settings key, not CLAUDE_CODE_AUTO_COMPACT_WINDOW: the env var
      # outranks `/autocompact` and `--autocompact`, so per-session overrides
      # would stop working (FR-011).
      programs.claude-code.settings.autoCompactWindow = cfg.autoCompactTokens;
    }

    (lib.mkIf cfg.statusLine.enable {
      programs.claude-code.settings.statusLine = {
        type = "command";
        command = lib.getExe contextStatusline;
      };
    })
  ];
}
