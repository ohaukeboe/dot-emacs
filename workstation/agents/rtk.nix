{
  lib,
  pkgs,
  ...
}:
{
  agents.extraClaudeDocs = [ ./rtk-docs.md ];

  home.packages = [ pkgs.rtk ];

  programs.claude-code.settings.hooks.PreToolUse = [
    {
      matcher = "Bash";
      hooks = [ { type = "command"; command = "rtk hook claude"; } ];
    }
  ];

  home.activation.rtkHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --hook-only
    $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --opencode --hook-only
  '';
}
