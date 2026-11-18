{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.mango;
in
{
  options.modules.mango = {
    enable = mkEnableOption "Mango window manager session";

    greeter.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether this module provides the login screen (greetd and the
        Quickshell greeter, quickshell/greeter.qml). It lists every installed
        session, so COSMIC stays selectable.
      '';
    };

    terminal = mkPackageOption pkgs "foot" { };

    # The range cosmic-pass enforces (config::CLIPBOARD_CLEAR_RANGE).
    pass.clipboardClearSeconds = mkOption {
      type = types.ints.between 10 600;
      default = 90;
      description = ''
        Seconds a secret copied from the Proton Pass quick access stays on
        the clipboard (specs/016-proton-pass-quick-access).
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.greeter.enable && config.services.displayManager.cosmic-greeter.enable);
        message = ''
          modules/mango/default.nix: modules.mango.greeter.enable and COSMIC's
          login screen are both on. Set modules.cosmic-de.greeter.enable = false
          for this machine in machines/machines.nix, or set
          modules.mango.greeter.enable = false.
        '';
      }
    ];

    programs.mango.enable = true;
    programs.mango.package =
      pkgs.expiringOverride
        {
          pkg = pkgs.mangowc;
          brokenAt = "0.18.5";
          reason = "deck tab strip slides along with a window moved into the stack";
        }
        (
          p:
          p.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./patches/deck-tab-strip-anchor.patch ];
          })
        );
    # Ships mango-session.target; nixpkgs' programs.mango does not add it.
    systemd.packages = [ config.programs.mango.package ];

    security.pam.services.greetd.enableGnomeKeyring = true;

    # Same values as modules/cosmic-de, so both merge: gnome-keyring for the
    # secret portal, but not its gcr-ssh-agent, which would take
    # SSH_AUTH_SOCK away from the Home Manager agent that signs git commits.
    services.gnome.gnome-keyring.enable = true;
    services.gnome.gcr-ssh-agent.enable = false;
    services.power-profiles-daemon.enable = true;
    # The Quickshell battery and Bluetooth widgets read these daemons; COSMIC
    # used to enable them, so they vanished when it was dropped.
    services.upower.enable = true;
    hardware.bluetooth.enable = true;
    # Also lost with COSMIC: dconf backs the Home Manager dconf.settings below,
    # gvfs gives GTK apps Trash and MTP/smb/sftp, noto-fonts the non-Latin
    # fallback glyphs.
    programs.dconf.enable = true;
    services.gvfs.enable = true;
    fonts.packages = [ pkgs.noto-fonts ];
    # pass-cli keeps its database key in this store; its default, kernel, is
    # the per-login session keyring, which a new login does not share, and a
    # store that changes forces a logout. dbus puts it in gnome-keyring above.
    environment.sessionVariables.PROTON_PASS_LINUX_KEYRING = "dbus";

    environment.systemPackages = [
      pkgs.adw-gtk3
      pkgs.adwaita-icon-theme
    ];

    home-manager.users.${config.user.username} = {
      # libadwaita reads these through the gtk portal's Settings under Mango;
      # COSMIC answers Settings from its own portal, so they do not affect it.
      dconf.settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        cursor-theme = "Adwaita";
        cursor-size = 24;
      };
    };
  };
}
