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
      ];

      # Wallpaper: flat dark color on every output. Declared here so new
      # machines come up with the same background instead of the COSMIC
      # default image. Note these files become read-only symlinks, so the
      # wallpaper can only be changed by editing this module.
      xdg.configFile = {
        "cosmic/com.system76.CosmicBackground/v1/all".text = ''
          (
              output: "all",
              source: Color(Single((0.09, 0.09, 0.09))),
              filter_by_theme: false,
              rotation_frequency: 900,
              filter_method: Lanczos,
              scaling_mode: Zoom,
              sampling_method: Alphanumeric,
          )
        '';
        "cosmic/com.system76.CosmicBackground/v1/same-on-all".text = "true";

        # Keyboard: EU layout, Caps Lock as an extra Ctrl, faster repeat.
        "cosmic/com.system76.CosmicComp/v1/xkb_config".text = ''
          (
              rules: "",
              model: "pc104",
              layout: "eu",
              variant: "",
              options: Some("terminate:ctrl_alt_bksp,caps:ctrl_modifier"),
              repeat_delay: 600,
              repeat_rate: 25,
          )
        '';

        # Tiling and workspace behaviour: autotile per workspace, vertical
        # per-output workspaces, focus following the cursor and back.
        "cosmic/com.system76.CosmicComp/v1/autotile".text = "true";
        "cosmic/com.system76.CosmicComp/v1/autotile_behavior".text = "PerWorkspace";
        "cosmic/com.system76.CosmicComp/v1/cursor_follows_focus".text = "true";
        "cosmic/com.system76.CosmicComp/v1/focus_follows_cursor".text = "true";
        "cosmic/com.system76.CosmicComp/v1/focus_follows_cursor_delay".text = "20";
        "cosmic/com.system76.CosmicComp/v1/workspaces".text = ''
          (
              workspace_mode: OutputBound,
              workspace_layout: Vertical,
          )
        '';

        # Custom keyboard shortcuts. Super+space opens the Proton Pass wofi
        # picker declared in workstation/home.nix.
        "cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom".text = ''
          {
              (
                  modifiers: [
                      Super,
                  ],
                  key: "space",
                  description: Some("proton pass"),
              ): Spawn("protonpass-wofi"),
              (
                  modifiers: [
                      Super,
                      Shift,
                  ],
                  key: "space",
                  description: Some("1password"),
              ): Spawn("1password --quick-access"),
          }
        '';
      };

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
