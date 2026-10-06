# Claude Pointer: pick an element in Zen, comment on it, and send the comment
# into a running Claude Code session. https://github.com/ohaukeboe/claude-pointer
#
# Replaces `claude-pointer install`, which writes the same files but points
# them at a mutable node path. Start a session with `claude-pointer claude`.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  claude-pointer = pkgs.callPackage ./packages/claude-pointer.nix { src = inputs.claude-pointer; };
in
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.packages = [ claude-pointer ];

  # Read by `claude-pointer claude`, which passes it to `claude --mcp-config`.
  xdg.configFile."claude-pointer/mcp.json".source = "${claude-pointer}/share/claude-pointer/mcp.json";

  programs.zen-browser = {
    nativeMessagingHosts = [ claude-pointer ];

    # The extension is unsigned. Zen builds without MOZ_REQUIRE_SIGNING, so
    # the pref below is enough to let it install.
    policies = {
      Preferences."xpinstall.signatures.required" = {
        Value = false;
        Status = "locked";
      };
      ExtensionSettings.${claude-pointer.extensionId} = {
        installation_mode = "force_installed";
        install_url = "file://${claude-pointer}/share/claude-pointer/claude-pointer.xpi";
      };
    };
  };
}
