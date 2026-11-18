# Portal routing for the Mango session, and the screen-share picker.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.mango;

  # nixpkgs' programs.mango spells the key "ScreenShot", which no backend
  # declares, so Screenshot fell through to gtk (which lacks it).
  mangoPortals = {
    default = [ "gtk" ];
    "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
    "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
    "org.freedesktop.impl.portal.Inhibit" = [ "gtk" ];
    "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
  };

  # Fails the build when a portal key names an interface its backend's
  # .portal file does not declare (the ScreenShot typo class).
  portalCheck =
    let
      portals = pkgs.symlinkJoin {
        name = "mango-portals";
        paths = config.xdg.portal.extraPortals;
      };
      checks = concatStrings (
        mapAttrsToList (
          iface: backends:
          optionalString (hasPrefix "org.freedesktop.impl.portal." iface) (
            concatMapStrings (b: ''
              if ! grep -qE '^Interfaces=(.*;)?${iface}(;|$)' "$dir/${b}.portal"; then
                echo "modules/mango/portal.nix: xdg.portal.config.mango: ${b}.portal does not declare ${iface}; fix the key spelling or the backend" >&2
                exit 1
              fi
            '') (filter (b: b != "none" && b != "*") (toList backends))
          )
        ) config.xdg.portal.config.mango
      );
    in
    pkgs.runCommand "mango-portal-check" { } ''
      dir=${portals}/share/xdg-desktop-portal/portals
      ${checks}
      touch $out
    '';
in
{
  config = mkIf cfg.enable {
    xdg.portal.config.mango = mkForce mangoPortals;
    # xdpw finds pickers on PATH, which its user service does not share.
    # xdpw 0.8 wants "Monitor: <name>" or "Window: <title>" lines back.
    # The profile path, not the store path: a switch does not restart this
    # user service, so a store path would stay stale until the next login.
    # programs.mango adds the portal package only; enable is what passes
    # these settings to the service as --config.
    xdg.portal.wlr.enable = true;
    xdg.portal.wlr.settings.screencast = {
      chooser_type = "dmenu";
      chooser_cmd = "/etc/profiles/per-user/${config.user.username}/bin/mango-pick --layout sources 'Share your screen'";
    };
    system.extraDependencies = [ portalCheck ];
  };
}
