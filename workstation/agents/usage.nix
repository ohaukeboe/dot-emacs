# Claude usage for the Mango rail (specs/013-mango-islands-shell): a timer
# reads the plan limits from Anthropic's OAuth usage endpoint and counts
# tokens from the session transcripts; the status line also saves the rate
# limits when Claude Code passes them (statusline.nix), which it does only
# near a limit. Both write under $XDG_STATE_HOME/agent-usage, the
# only interface to modules/mango (contracts/usage-record.md).
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.usage;

  collector = pkgs.callPackage ./packages/agent-usage-tokens.nix { };
in
{
  options.agents.usage.enable = lib.mkEnableOption ''
    Claude usage records for the desktop rail: rate limits from the status
    line and token counts from the session transcripts
  '';

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.agents.context.statusLine.enable;
        message = ''
          agents.usage.enable needs agents.context.statusLine.enable: the rate limits
          come from the status line (workstation/agents/statusline.nix). Turn the status
          line on or agents.usage off.
        '';
      }
    ];

    systemd.user.services.agent-usage = {
      Unit.Description = "Read Claude plan limits and count tokens for the usage popup";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe collector;
      };
    };

    systemd.user.timers.agent-usage = {
      Unit.Description = "Refresh Claude usage every 5 minutes";
      Timer = {
        OnStartupSec = "1min";
        OnUnitActiveSec = "5min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
