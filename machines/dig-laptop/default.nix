{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hmConfig = config.home-manager.users.${config.user.username};
in

{
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
  ];

  # oslokommune/claude-marketplace, registered as `dig`. Work plugins, so only
  # on the work machine. No plugin is enabled here: projects enable the ones
  # they need in their own .claude/settings.json.
  home-manager.users.${config.user.username} = {
    programs.claude-code.marketplaces.dig = inputs.oslokommune-claude-marketplace;

    # Daily Claude usage report to oslokommune/claude-leaderboard, which decides
    # Premium seats. Sends metadata only (tokens, model, request count, estimated
    # cost). uvx fetches the tool from main over SSH on each run, so the github.com
    # key must be in the agent (ssh-add-keys, workstation/ssh.nix). The first run
    # registers the work email interactively and must be done by hand:
    #   uvx --from "git+ssh://git@github.com/oslokommune/claude-leaderboard@main#subdirectory=claude-usage-tracker" sync-usage
    systemd.user = {
      services.claude-leaderboard-sync = {
        Unit = {
          Description = "Report Claude Code usage to the DIG leaderboard";
          After = [
            "network-online.target"
            "ssh-add-keys.service"
          ];
          Wants = [ "ssh-add-keys.service" ];
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "SSH_AUTH_SOCK=%t/${hmConfig.services.ssh-agent.socket}"
            "PATH=${
              lib.makeBinPath [
                pkgs.git
                pkgs.openssh
              ]
            }"
          ];
          ExecStart = lib.escapeShellArgs [
            (lib.getExe' pkgs.uv "uvx")
            "--from"
            "git+ssh://git@github.com/oslokommune/claude-leaderboard@main#subdirectory=claude-usage-tracker"
            "sync-usage"
            "--days"
            "7"
          ];
        };
      };

      timers.claude-leaderboard-sync = {
        Unit.Description = "Report Claude Code usage to the DIG leaderboard daily";
        Timer = {
          OnCalendar = "*-*-* 11:00:00";
          # A laptop is often asleep at 11: catch up on the next wake.
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
  };
}
