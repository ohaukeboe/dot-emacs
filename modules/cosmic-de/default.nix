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
  homeDir = config.users.users.${config.user.username}.home;

  # COSMIC stores one setting per file under ~/.config/cosmic/<component>/v1/<key>.
  # Declaring a key here makes it a read-only symlink: COSMIC can no longer
  # change that setting at runtime, so only pin settings that should be the
  # same on every machine.
  cosmicFiles =
    component: mapAttrs' (key: value: nameValuePair "cosmic/${component}/v1/${key}" { text = value; });

  cosmic-pass = inputs.cosmic-pass.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
    # gnome-keyring pulls in gcr-ssh-agent by default, whose socket unit runs
    # `systemctl --user set-environment SSH_AUTH_SOCK=%t/gcr/ssh` and so
    # hijacks the session away from the Home Manager ssh-agent that
    # ssh-add-keys loads the sops keys into. Result: an empty agent and
    # `error: Couldn't find key in agent?` on every signed git commit.
    services.gnome.gcr-ssh-agent.enable = false;

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
    environment.systemPackages = [
      pkgs.cutecosmic
      pkgs.adw-gtk3
      cosmic-pass
    ];

    # cosmic-pass ships a user service for its background popup process; the
    # shortcut below only toggles it. pass-cli (workstation/home.nix) must be
    # logged in, and gnome-keyring above holds its cache key.
    systemd.packages = [ cosmic-pass ];
    systemd.user.services.cosmic-pass.wantedBy = [ "graphical-session.target" ];

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

      xdg.configFile = mkMerge [
        # Wallpaper: flat dark color on every output. Declared here so new
        # machines come up with the same background instead of the COSMIC
        # default image.
        (cosmicFiles "com.system76.CosmicBackground" {
          all = ''
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
          same-on-all = "true";
        })

        (cosmicFiles "com.system76.CosmicComp" {
          # Keyboard: EU layout, Caps Lock as an extra Ctrl, faster repeat.
          xkb_config = ''
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
          autotile = "true";
          autotile_behavior = "PerWorkspace";
          cursor_follows_focus = "true";
          focus_follows_cursor = "true";
          focus_follows_cursor_delay = "20";
          workspaces = ''
            (
                workspace_mode: OutputBound,
                workspace_layout: Vertical,
            )
          '';

          # Touchpad: click zones by finger count, natural two-finger scroll.
          input_touchpad = ''
            (
                state: Enabled,
                click_method: Some(Clickfinger),
                scroll_config: Some((
                    method: Some(TwoFinger),
                    natural_scroll: Some(true),
                    scroll_button: None,
                    scroll_factor: None,
                )),
            )
          '';
        })

        # Custom keyboard shortcuts. Super+space toggles the cosmic-pass
        # Proton Pass quick-access popup.
        (cosmicFiles "com.system76.CosmicSettings.Shortcuts" {
          custom = ''
            {
                (
                    modifiers: [
                        Super,
                    ],
                    key: "space",
                    description: Some("proton pass"),
                ): Spawn("cosmic-pass"),
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
        })

        # Only the top panel; no dock.
        (cosmicFiles "com.system76.CosmicPanel" {
          entries = ''
            [
                "Panel",
            ]
          '';
        })

        # Top panel: thin, always visible, full width. `output` is left out on
        # purpose so each machine can bind the panel to its own display.
        (cosmicFiles "com.system76.CosmicPanel.Panel" {
          name = ''"Panel"'';
          anchor = "Top";
          anchor_gap = "false";
          layer = "Top";
          size = "XS";
          size_center = "None";
          size_wings = "None";
          spacing = "0";
          padding = "0";
          padding_overlap = "0.5";
          margin = "0";
          border_radius = "0";
          opacity = "1.0";
          background = "ThemeDefault";
          expand_to_edges = "true";
          exclusive_zone = "true";
          keep_style_on_maximize = "false";
          keyboard_interactivity = "OnDemand";
          autohide = "Never";
          autohover_delay_ms = "Some(500)";
          autohide_behavior = ''
            (
                wait_time: 1000,
                transition_time: 200,
                handle_size: 4,
                unhide_delay: 200,
            )
          '';
          plugins_center = ''
            Some([
                "com.system76.CosmicAppletTime",
            ])
          '';
          plugins_wings = ''
            Some(([
                "com.system76.CosmicAppletWorkspaces",
                "com.system76.CosmicPanelAppButton",
            ], [
                "io.github.nwxnw.cosmic-ext-connected",
                "com.system76.CosmicAppletInputSources",
                "com.system76.CosmicAppletStatusArea",
                "com.system76.CosmicAppletTiling",
                "com.system76.CosmicAppletAudio",
                "com.system76.CosmicAppletNetwork",
                "com.system76.CosmicAppletBattery",
                "com.system76.CosmicAppletNotifications",
                "com.system76.CosmicAppletBluetooth",
                "com.system76.CosmicAppletPower",
            ]))
          '';
        })

        # Theme source values. cosmic-settings derives the full
        # com.system76.CosmicTheme.{Dark,Light}/* palettes from these, so only
        # the builder inputs are pinned.
        (cosmicFiles "com.system76.CosmicTheme.Dark.Builder" {
          accent = ''
            Some((
                red: 0.7921569,
                green: 0.7294118,
                blue: 0.7058824,
            ))
          '';
          bg_color = ''
            Some((
                red: 0.09019608,
                green: 0.09019608,
                blue: 0.09019608,
                alpha: 1.0,
            ))
          '';
          gaps = "(0, 2)";
          active_hint = "2";
        })

        (cosmicFiles "com.system76.CosmicTheme.Light.Builder" {
          gaps = "(0, 2)";
          active_hint = "2";
        })

        # Toolkit: theme GTK/Qt apps from the COSMIC theme, COSMIC icon set.
        (cosmicFiles "com.system76.CosmicTk" {
          apply_theme_global = "true";
          icon_theme = ''"Cosmic"'';
        })

        # Clock applet: 24-hour time, weeks start on Monday.
        (cosmicFiles "com.system76.CosmicAppletTime" {
          military_time = "true";
          first_day_of_week = "0";
        })

        # File manager sidebar shortcuts.
        (cosmicFiles "com.system76.CosmicFiles" {
          favorites = ''
            [
                Home,
                Documents,
                Downloads,
                Music,
                Pictures,
                Videos,
                Path("${homeDir}/Nextcloud"),
                Path("${homeDir}/projects"),
            ]
          '';
        })
      ];
    };
  };
}
