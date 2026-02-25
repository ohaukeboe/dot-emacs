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
      inputs.cutecosmic.packages.${pkgs.stdenv.hostPlatform.system}.default
      adw-gtk3
    ];

    home-manager.users.${config.user.username} = {
      services.flatpak.packages = [
        "org.gtk.Gtk3theme.adw-gtk3"
        "org.gtk.Gtk3theme.adw-gtk3-dark"
      ];
    };
  };
}
