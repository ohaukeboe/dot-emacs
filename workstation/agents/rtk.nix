{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.tools.rtk;
in
{
  agents.tools.rtk = {
    packages = [ pkgs.rtk ];
    docs.both = [ ./rtk-docs.md ];
    hooks.PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "${pkgs.rtk}/bin/rtk hook claude";
          }
        ];
      }
    ];
  };

  home.activation.rtkHook = lib.mkIf cfg.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --hook-only
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --opencode --hook-only
    ''
  );
}
