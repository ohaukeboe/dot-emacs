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

  home.activation.rtkHook = lib.mkIf cfg.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --hook-only
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --opencode --hook-only
    ''
  );
}
