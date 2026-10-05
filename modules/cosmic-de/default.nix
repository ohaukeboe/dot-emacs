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

  # COSMIC stores one setting per file under ~/.config/cosmic/<component>/v1/<key>
  # and, for a key missing there, falls back to the same path under the first
  # XDG data dir that has the component (here /run/current-system/sw/share).
  # The settings below are shipped there as system defaults: COSMIC starts
  # with them, and a change made in cosmic-settings is saved to ~/.config and
  # wins over them.
  cosmicFiles = component: keys: { ${component} = keys; };

  cosmicSettings = mergeAttrsList [
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

      # Touchpad: click zones by finger count, natural two-finger scroll,
      # tap to click with tap-and-drag.
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
            tap_config: Some((
                enabled: true,
                button_map: Some(LeftRightMiddle),
                drag: true,
                drag_lock: false,
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

    # Theme source values. The full com.system76.CosmicTheme.{Dark,Light}/*
    # palettes are built from these in cosmicDefaults below, so only the
    # builder inputs are pinned.
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

  cosmicSettingsFiles = pkgs.runCommand "cosmic-settings-files" { } (
    concatStrings (
      flatten (
        mapAttrsToList (
          component:
          mapAttrsToList (
            key: value: ''
              install -Dm644 ${pkgs.writeText "${component}-${key}" value} \
                $out/share/cosmic/${component}/v1/${key}
            ''
          )
        ) cosmicSettings
      )
    )
  );

  # COSMIC reads the derived com.system76.CosmicTheme.{Dark,Light} palettes,
  # not the *.Builder keys above; only cosmic-settings turns one into the
  # other, and only when a value is changed in its UI. Build the palettes here
  # so the pinned accent and background are part of the defaults. The builder
  # keys not pinned above come from cosmic-settings, as they do at runtime.
  cosmicDefaults =
    pkgs.runCommand "cosmic-defaults"
      {
        nativeBuildInputs = [ pkgs.cosmic-ext-ctl ];
        builderInputs = pkgs.symlinkJoin {
          name = "cosmic-theme-builder-inputs";
          # symlinkJoin keeps the first link for a path, so pinned keys win.
          paths = [
            cosmicSettingsFiles
            pkgs.cosmic-settings
          ];
        };
      }
      ''
        export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config
        export XDG_DATA_DIRS=$builderInputs/share
        cosmic-ctl build-theme

        mkdir -p $out/share/cosmic
        cp -r --no-preserve=mode ${cosmicSettingsFiles}/share/cosmic/. $out/share/cosmic/
        cp -r $XDG_CONFIG_HOME/cosmic/com.system76.CosmicTheme.{Dark,Light} $out/share/cosmic/
      '';

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
    # Backend for COSMIC's power applet. Without it the applet has no way to
    # switch profiles, so on ThinkPads the firmware's DYTC thermal management
    # (/sys/firmware/acpi/platform_profile) stays pinned to "balanced" and
    # never drops the fan curve on battery.
    services.power-profiles-daemon.enable = true;
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
      # pass-cli keeps the key to its own database in the store this names, and
      # its default, kernel, means the caller's kernel session keyring -- which
      # a systemd user service never shares with the terminal a login ran in,
      # so the cosmic-pass service failed every call with "Error creating
      # client features". cosmic-pass itself passes dbus; this makes a terminal
      # pass-cli agree, since the two stores must match or pass-cli force-logs
      # out. Changing the value costs one sign-in.
      PROTON_PASS_LINUX_KEYRING = "dbus";
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
      # hiPrio: the same key paths also ship in cosmic-settings and other
      # COSMIC packages, and these defaults must win in the merged
      # /run/current-system/sw/share/cosmic.
      (hiPrio cosmicDefaults)
    ];

    # cosmic-pass ships a user service for its background popup process; the
    # shortcut below only toggles it. pass-cli (workstation/home.nix) must be
    # logged in, and gnome-keyring above holds both its cache key and, through
    # PROTON_PASS_LINUX_KEYRING above, pass-cli's own database key.
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
        # Only published on the cosmic remote; without origin nix-flatpak
        # looks for it on flathub and retries forever.
        {
          appId = "io.github.nwxnw.cosmic-ext-connected";
          origin = "cosmic";
        }
      ];
    };
  };
}
