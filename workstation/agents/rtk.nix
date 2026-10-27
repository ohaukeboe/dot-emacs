{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.tools.rtk;

  # A stage of the chain rather than its own PreToolUse hook: matching hooks
  # run in parallel and the winning updatedInput is undefined, so this and the
  # process cap would race each other. See
  # docs/adr/0003-agent-bash-rewriter-chain.md.
  stage = pkgs.writeShellApplication {
    name = "agent-bash-rewriter-rtk";
    text = ''
      exec ${pkgs.rtk}/bin/rtk hook claude "$@"
    '';
  };

  # rtk prints "No hook installed" on stderr, so into every shell result,
  # because it recognises only a literal `rtk hook claude` PreToolUse command
  # and here it runs inside agent-bash-rewriter-chain. Its once-a-day rate
  # limit cannot help either: the sandbox's read-only ~/.local/share stops it
  # stamping rtk/.hook_warn_last. rtk's own switch silences the banner without
  # touching compression; widening the sandbox for noise is not worth it.
  # tests/rtk-banner.nix checks both the warning path and the switch.
  suppressVar = "RTK_SUPPRESS_HOOK_WARNING";
in
{
  agents.tools.rtk = {
    packages = [ pkgs.rtk ];
    docs.both = [ ./rtk-docs.md ];
  };

  agents.bashRewriters = lib.mkIf cfg.enable {
    rtk = {
      order = 50;
      executable = stage;
    };
  };

  programs.claude-code.settings.env = lib.mkIf cfg.enable {
    ${suppressVar} = "1";
  };

  home.activation.rtkHook = lib.mkIf cfg.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --hook-only
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --opencode --hook-only
    ''
  );
}
