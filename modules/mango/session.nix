# The user services and tools of the session: terminal, lock, clipboard, tray.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.mango;

  inherit (import ./common.nix { inherit config lib pkgs; })
    palette
    sessionTarget
    lockScreen
    bindToSession
    screenshot
    reload
    displaySetup
    pick
    powerMenu
    clipPick
    ;

  # swayidle's idle timer restarts on every input, and locking is input, so
  # this blanks the outputs 5 minutes after the lock unless someone touches
  # the machine. It does nothing while unlocked.
  blankWhenLocked = pkgs.writeShellApplication {
    name = "mango-blank-when-locked";
    runtimeInputs = [
      pkgs.quickshell
      pkgs.wlopm
      pkgs.procps
      pkgs.coreutils
    ];
    text = ''
      if [[ $(timeout 2 qs -c mango ipc call lock secure 2>/dev/null) == true ]] ||
        pgrep -x swaylock >/dev/null; then
        wlopm --off '*'
      fi
    '';
  };

in
{
  config = mkIf cfg.enable {
    # mango-lock is the Quickshell lock screen (Lock.qml); swaylock is its
    # fallback when Quickshell is not running.
    security.pam.services.mango-lock = { };
    security.pam.services.swaylock = { };

    home-manager.users.${config.user.username} = {
      home.packages = [
        cfg.terminal
        screenshot
        clipPick
        displaySetup
        reload
        pick
        powerMenu
        pkgs.pwvucontrol
      ];

      # The displays card (quickshell/DisplaysCard.qml) in the launcher; it
      # took wdisplays' place (specs/018-display-layout-card).
      xdg.desktopEntries.mango-displays = {
        name = "Displays";
        genericName = "Display layout";
        exec = "${getExe pkgs.quickshell} -c mango ipc call displays toggle";
        icon = "video-display";
        categories = [ "Settings" ];
      };

      services.wl-clip-persist = {
        enable = true;
        clipboardType = "regular";
        systemdTargets = [ sessionTarget ];
      };

      programs.satty.enable = true;

      programs.foot = {
        # cfg.terminal may be another terminal; this styles foot only.
        enable = getName cfg.terminal == "foot";
        package = cfg.terminal;
        settings = {
          main = {
            font = "RobotoMono Nerd Font:size=10";
            pad = "24x24";
          };
          # foot 1.28 reads [colors-dark]; [colors] is the deprecated name.
          colors-dark = {
            background = palette.app;
            foreground = palette.fg;
          };
        };
      };

      programs.swaylock = {
        enable = true;
        settings.color = palette.frame;
      };

      services.swayidle = {
        enable = true;
        systemdTargets = [ sessionTarget ];
        events.before-sleep = getExe lockScreen;
        timeouts = [
          {
            timeout = 300;
            command = getExe blankWhenLocked;
            resumeCommand = "${getExe pkgs.wlopm} --on '*'";
          }
        ];
      };

      # `cliphist store` skips what `wl-paste --watch` marks
      # CLIPBOARD_STATE=sensitive (a password manager's
      # x-kde-passwordManagerHint), which keeps passwords out of the picker's
      # clipboard layout (specs/015-picker-layouts research R3).
      services.cliphist = {
        enable = true;
        systemdTargets = [ sessionTarget ];
      };

      services.hyprpolkitagent.enable = true;
      systemd.user.services.hyprpolkitagent = bindToSession;

      services.network-manager-applet.enable = true;
      systemd.user.services.network-manager-applet = bindToSession;
    };
  };
}
