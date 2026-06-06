{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  cfg = config.modules.cosmic-de;
in
{
  options.modules.cosmic-de = {
    enable = mkEnableOption "COSMIC Desktop Environment";
  };

  config = mkIf cfg.enable {
    # COSMIC Desktop Environment
    services.displayManager.cosmic-greeter.enable = true;
    services.desktopManager.cosmic.enable = true;
    services.system76-scheduler.enable = true;
    services.gnome.gnome-keyring.enable = true;

    # Qt theming for COSMIC
    environment.sessionVariables = {
      QT_QPA_PLATFORMTHEME = "cosmic";
      COSMIC_DATA_CONTROL_ENABLED = 1; # Clipboard management
      GTK_THEME = "adw-gtk3-dark";
    };

    # XDG Desktop Portal configuration for COSMIC
    xdg.portal.wlr.enable = true;
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-cosmic ];
    xdg.portal.config.common.default = "cosmic";
    xdg.portal.enable = true;

    # COSMIC-specific packages
    environment.systemPackages = with pkgs; [
      cutecosmic
      adw-gtk3
    ];

    home-manager.users.${config.user.username} = {
      services.flatpak.remotes = [
        # Default flathub remote must be re-declared: assigning `remotes`
        # replaces nix-flatpak's default instead of merging with it.
        {
          name = "flathub";
          location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
        }
        {
          name = "cosmic";
          location = "https://apt.pop-os.org/cosmic/cosmic.flatpakrepo";
        }
      ];

      services.flatpak.packages = [
        "org.gtk.Gtk3theme.adw-gtk3"
        "org.gtk.Gtk3theme.adw-gtk3-dark"
        "io.github.nwxnw.cosmic-ext-connected"
        "io.github.cosmic_utils.cosmic-ext-applet-clipboard-manager"
        "io.github.TopiCsarno.YapCap"
      ];

      # Fallback polkit agent (cosmic-osd's built-in agent crashes)
      systemd.user.services.polkit-agent = {
        Unit = {
          Description = "LXQt Polkit authentication agent";
          After = [ "graphical-session-pre.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.lxqt.lxqt-policykit}/bin/lxqt-policykit-agent";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
