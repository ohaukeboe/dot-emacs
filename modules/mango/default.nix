{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.mango;

  # Every session service below is tied to this target, which mango starts
  # itself (and which the mango package ships, see systemd.packages below).
  # graphical-session.target would also start them under COSMIC.
  sessionTarget = "mango-session.target";

  # Flat palette: bg is the frame (wallpaper, gaps, bar), card the windows on it.
  bg = "111416";
  card = "191d20";
  accent = "c17e7e";

  terminal = getExe cfg.terminal;
  swaylock = "${getExe pkgs.swaylock} -f";
  swayosd = getExe' pkgs.swayosd "swayosd-client";
  playerctl = getExe pkgs.playerctl;
  mango = config.programs.mango.package;
  panel = cfg.displays.internal;

  inherit
    (import ./scripts.nix {
      inherit
        lib
        pkgs
        mango
        panel
        ;
      systemd = config.systemd.package;
    })
    screenshot
    lidSync
    reload
    displaySetup
    powerMenu
    clipPick
    ;

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
                echo "modules/mango/default.nix: xdg.portal.config.mango: ${b}.portal does not declare ${iface}; fix the key spelling or the backend" >&2
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

  # Quick-controls and calendar popups for the rail (specs/012-mango-rail-bar).
  quickshellDir = pkgs.runCommand "mango-quickshell" { } ''
    mkdir $out
    cp ${
      pkgs.replaceVars ./quickshell/shell.qml {
        inherit bg card accent;
        mmsg = getExe' mango "mmsg";
        brightnessctl = getExe pkgs.brightnessctl;
        powerMenu = getExe powerMenu;
      }
    } $out/shell.qml
  '';
  # Waybar left-aligns labels in a vertical bar; the rail centres them.
  centered = {
    align = 0.5;
    justify = "center";
  };
  popupToggle = target: "${getExe' pkgs.quickshell "qs"} -c mango ipc call ${target} toggle";

  # Fails the build on any qmllint warning in the popups. Two categories are
  # off: Quickshell's PanelWindow is registered uncreatable and BluetoothAdapter
  # is not exposed to qmllint, though both work at runtime.
  qmlCheck = pkgs.runCommand "mango-qml-check" { } ''
    if ! ${pkgs.qt6.qtdeclarative}/bin/qmllint \
        -I ${pkgs.quickshell}/lib/qt-6/qml \
        -I ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
        --max-warnings 0 \
        --unresolved-type disable \
        --uncreatable-type disable \
        ${quickshellDir}/shell.qml; then
      echo "modules/mango/quickshell/shell.qml: qmllint failed; fix the QML" >&2
      exit 1
    fi
    touch $out
  '';

  kanshiProfile = name: outputs: {
    profile = {
      inherit name outputs;
      exec = [ (getExe lidSync) ];
    };
  };

  kanshiOutput =
    o:
    {
      inherit (o) criteria;
      status = if o.enable then "enable" else "disable";
      position = "${toString o.position.x},${toString o.position.y}";
    }
    // optionalAttrs (o.mode != null) { inherit (o) mode; }
    // optionalAttrs (o.scale != null) { scale = o.scale * 1.0; };

  outputType = types.submodule {
    options = {
      criteria = mkOption {
        type = types.nonEmptyStr;
        description = ''Output name or "Make Model Serial", as kanshi(5) matches.'';
      };
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      mode = mkOption {
        type = types.nullOr (types.strMatching "[0-9]+x[0-9]+(@[0-9.]+(Hz)?)?");
        default = null;
        description = "WxH[@R]; null uses the preferred mode.";
      };
      # Unsigned: XWayland misplaces clicks on negative coordinates (mango docs).
      position = {
        x = mkOption {
          type = types.ints.unsigned;
          default = 0;
        };
        y = mkOption {
          type = types.ints.unsigned;
          default = 0;
        };
      };
      scale = mkOption {
        type = types.nullOr types.numbers.positive;
        default = null;
      };
    };
  };

  # Proton Pass: the quick-access popup the COSMIC module binds (cosmic-pass)
  # is a COSMIC applet from a flake input, not nixpkgs, so Mango opens the
  # full nixpkgs app instead (specs/010-mango-wm-session research R5).
  protonPass = getExe pkgs.proton-pass;
  onePassword = "${getExe' config.programs._1password-gui.package "1password"} --quick-access";

  # Mango's key=value config. Keys may repeat (bind, env, exec_once), so it
  # is a list of lines rather than an attrset.
  mangoLines = [
    # Keyboard and touchpad, the same values as modules/cosmic-de.
    "xkb_rules_layout=eu"
    "xkb_rules_options=terminate:ctrl_alt_bksp,caps:ctrl_modifier"
    "repeat_delay=600"
    "repeat_rate=25"
    "tap_to_click=1"
    "tap_and_drag=1"
    "drag_lock=0"
    "trackpad_natural_scrolling=1"
    "trackpad_disable_while_typing=1"

    # The COSMIC module sets QT_QPA_PLATFORMTHEME=cosmic system-wide.
    "env=QT_QPA_PLATFORMTHEME,gtk3"
    # Theming lives here, not in COSMIC, so COSMIC can be turned off.
    "env=GTK_THEME,adw-gtk3-dark"
    "env=XCURSOR_THEME,Adwaita"
    "env=XCURSOR_SIZE,24"
    "cursor_theme=Adwaita"
    "cursor_size=24"
    "border_radius=14"
    "border_px=2"
    # Card-coloured, so a border only shows on the focused window.
    "border_color=0x${card}ff"
    "focus_color=0x${accent}ff"
    "gap_inner_horizontal=14"
    "gap_inner_vertical=14"
    "gap_outer_horizontal=14"
    "gap_outer_vertical=14"

    # Reloading resets outputs; Super+r runs mango-reload instead.
    "auto_reload_config=0"
    # No monitor_rule on purpose: unknown displays get Mango's auto placement
    # (right of the others); known setups are kanshi profiles.

    "exec_once=${getExe pkgs.swaybg} -c '#${bg}'"
    "exec_once=${getExe lidSync}"
    "switchbind=fold,spawn,${getExe lidSync}"
    "switchbind=unfold,spawn,${getExe lidSync} open"

    "bind=SUPER,r,spawn,${getExe reload}"
    "bind=SUPER+SHIFT,Escape,spawn,${getExe powerMenu}"
    "bind=CTRL,Print,spawn,${getExe screenshot} annotate"
    "bind=SUPER+SHIFT,e,quit"
    "bind=SUPER,Return,spawn,${terminal}"
    "bind=SUPER,d,spawn,${getExe pkgs.fuzzel}"
    "bind=SUPER,q,killclient,"
    "bind=SUPER,Tab,focusstack,next"
    "bind=SUPER,f,togglefullscreen,"
    "bind=SUPER+SHIFT,f,togglefloating,"
    "bind=SUPER,Escape,spawn,${swaylock}"
    "bind=SUPER,v,spawn,${getExe clipPick}"
    "bind=NONE,Print,spawn,${getExe screenshot} full"
    "bind=SHIFT,Print,spawn,${getExe screenshot} region"
    # The laptop's Fn+F6 screenshot key sends Super+Shift+S, not Print.
    "bind=SUPER+SHIFT,s,spawn,${getExe screenshot} region"
    "bind=SUPER,space,spawn,${protonPass}"
    "bind=SUPER+SHIFT,space,spawn,${onePassword}"

    "bindl=NONE,XF86AudioRaiseVolume,spawn,${swayosd} --output-volume raise"
    "bindl=NONE,XF86AudioLowerVolume,spawn,${swayosd} --output-volume lower"
    "bindl=NONE,XF86AudioMute,spawn,${swayosd} --output-volume mute-toggle"
    "bindl=NONE,XF86AudioMicMute,spawn,${swayosd} --input-volume mute-toggle"
    "bindl=NONE,XF86MonBrightnessUp,spawn,${swayosd} --brightness raise"
    "bindl=NONE,XF86MonBrightnessDown,spawn,${swayosd} --brightness lower"
    "bindl=NONE,XF86AudioPlay,spawn,${playerctl} play-pause"
    "bindl=NONE,XF86AudioNext,spawn,${playerctl} next"
    "bindl=NONE,XF86AudioPrev,spawn,${playerctl} previous"

    "mousebind=SUPER,btn_left,moveresize,curmove"
    "mousebind=SUPER,btn_right,moveresize,curresize"
  ]
  ++
    concatMap
      (
        dir:
        let
          d = toLower dir;
        in
        [
          "bind=SUPER,${dir},focusdir,${d}"
          "bind=SUPER+SHIFT,${dir},move_client,${d}"
        ]
      )
      [
        "Left"
        "Right"
        "Up"
        "Down"
      ]
  ++ concatMap (
    n:
    let
      i = toString n;
    in
    [
      "bind=SUPER,${i},view,${i},0"
      "bind=SUPER+SHIFT,${i},tag,${i},0"
    ]
  ) (range 1 9);

  # `mango -p` parses the config and exits; a typo fails the build.
  mangoConfig =
    pkgs.runCommand "mango-config.conf"
      {
        config = concatStringsSep "\n" mangoLines + "\n";
        passAsFile = [ "config" ];
      }
      ''
        export HOME=$TMPDIR
        ${getExe config.programs.mango.package} -c "$configPath" -p
        cp "$configPath" $out
      '';

  # For HM modules that hardcode graphical-session.target or
  # wayland.systemd.target in their unit.
  bindToSession = {
    Unit.PartOf = mkForce [ sessionTarget ];
    Unit.After = mkForce [ sessionTarget ];
    Install.WantedBy = mkForce [ sessionTarget ];
  };
in
{
  options.modules.mango = {
    enable = mkEnableOption "Mango window manager session";

    greeter.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether this module provides the login screen (greetd + ReGreet). It
        lists every installed session, so COSMIC stays selectable.
      '';
    };

    terminal = mkPackageOption pkgs "foot" { };

    displays = {
      internal = mkOption {
        type = types.nonEmptyStr;
        default = "eDP-1";
        description = "Output name of the laptop panel.";
      };

      setups = mkOption {
        type = types.attrsOf (
          types.submodule {
            options.outputs = mkOption {
              type = types.nonEmptyListOf outputType;
              description = "Every output of this setup; matched as a whole set.";
            };
          }
        );
        default = { };
        description = ''
          Known display setups, applied by kanshi when exactly these outputs
          are connected. Print the current one with `mango-display-setup <name>`.
          Unknown setups get Mango's auto placement (right of the panel).
        '';
      };
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
      {
        assertion = !(cfg.displays.setups ? undocked);
        message = ''
          modules/mango/default.nix: modules.mango.displays.setups.undocked is
          reserved for the generated panel-only profile; rename that setup.
        '';
      }
    ]
    ++ concatLists (
      mapAttrsToList (
        name: s:
        let
          crits = map (o: o.criteria) s.outputs;
        in
        [
          {
            assertion = length crits == length (unique crits);
            message = ''
              modules/mango/default.nix: modules.mango.displays.setups.${name} lists
              the same criteria twice; rename or remove the duplicate output.
            '';
          }
          {
            assertion = any (o: o.enable) s.outputs;
            message = ''
              modules/mango/default.nix: modules.mango.displays.setups.${name} has
              no enabled output; enable at least one.
            '';
          }
        ]
      ) cfg.displays.setups
    );

    programs.mango.enable = true;
    # Ships mango-session.target; nixpkgs' programs.mango does not add it.
    systemd.packages = [ config.programs.mango.package ];

    services.displayManager.regreet = mkIf cfg.greeter.enable {
      enable = true;
      theme = {
        package = pkgs.adw-gtk3;
        name = "adw-gtk3-dark";
      };
      settings.GTK.application_prefer_dark_theme = true;
    };
    security.pam.services.greetd.enableGnomeKeyring = true;

    # Same values as modules/cosmic-de, so both merge: gnome-keyring for the
    # secret portal, but not its gcr-ssh-agent, which would take
    # SSH_AUTH_SOCK away from the Home Manager agent that signs git commits.
    services.gnome.gnome-keyring.enable = true;
    services.gnome.gcr-ssh-agent.enable = false;
    services.power-profiles-daemon.enable = true;
    security.pam.services.swaylock = { };

    xdg.portal.config.mango = mkForce mangoPortals;
    # xdpw finds pickers on PATH, which its user service does not share.
    xdg.portal.wlr.settings.screencast = {
      chooser_type = "simple";
      chooser_cmd = "${getExe pkgs.slurp} -f %o -or";
    };
    system.extraDependencies = [
      portalCheck
      qmlCheck
    ];

    # swayosd writes /sys/class/backlight/*/brightness; its udev rule makes
    # that group-video writable.
    services.udev.packages = [ pkgs.swayosd ];
    users.users.${config.user.username}.extraGroups = [ "video" ];

    services.blueman.enable = true;

    environment.systemPackages = [
      pkgs.adw-gtk3
      pkgs.adwaita-icon-theme
    ];

    home-manager.users.${config.user.username} = {
      home.packages = [
        cfg.terminal
        screenshot
        clipPick
        displaySetup
        reload
        powerMenu
        pkgs.wdisplays
        pkgs.pwvucontrol
      ];

      # libadwaita reads these through the gtk portal's Settings under Mango;
      # COSMIC answers Settings from its own portal, so they do not affect it.
      dconf.settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        cursor-theme = "Adwaita";
        cursor-size = 24;
      };

      services.kanshi = {
        enable = true;
        systemdTarget = sessionTarget;
        settings = [
          (kanshiProfile "undocked" [
            {
              criteria = panel;
              status = "enable";
              position = "0,0";
            }
          ])
        ]
        ++ mapAttrsToList (name: s: kanshiProfile name (map kanshiOutput s.outputs)) cfg.displays.setups;
      };

      services.wl-clip-persist = {
        enable = true;
        clipboardType = "regular";
        systemdTargets = [ sessionTarget ];
      };

      services.swayosd.enable = true;
      systemd.user.services.swayosd = bindToSession;

      services.blueman-applet = {
        enable = true;
        systemdTargets = [ sessionTarget ];
      };

      programs.satty.enable = true;

      xdg.configFile."mango/config.conf".source = mangoConfig;

      programs.fuzzel = {
        enable = true;
        settings = {
          main.terminal = terminal;
          colors = {
            background = "${bg}ff";
            text = "ddddddff";
            selection = "333333ff";
            selection-text = "ffffffff";
            border = "${accent}ff";
          };
        };
      };

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
            background = "171717";
            foreground = "c8c5c7";
          };
        };
      };

      programs.swaylock = {
        enable = true;
        settings.color = bg;
      };

      services.swayidle = {
        enable = true;
        systemdTargets = [ sessionTarget ];
        events.before-sleep = swaylock;
      };

      services.mako = {
        enable = true;
        settings = {
          default-timeout = 5000;
          background-color = "#${bg}";
          text-color = "#dddddd";
          border-color = "#${accent}";
        };
      };

      services.cliphist = {
        enable = true;
        systemdTargets = [ sessionTarget ];
      };

      services.hyprpolkitagent.enable = true;
      systemd.user.services.hyprpolkitagent = bindToSession;

      services.network-manager-applet.enable = true;
      systemd.user.services.network-manager-applet = bindToSession;

      # COSMIC starts kdeconnectd from XDG autostart; Mango runs no autostart.
      services.kdeconnect = {
        enable = true;
        indicator = true;
      };
      systemd.user.services.kdeconnect = bindToSession;
      systemd.user.services.kdeconnect-indicator = bindToSession;

      programs.quickshell = {
        enable = true;
        configs.mango = quickshellDir;
        activeConfig = "mango";
        systemd = {
          enable = true;
          target = sessionTarget;
        };
      };

      # The rail: a narrow strip in the frame colour (specs/012-mango-rail-bar).
      programs.waybar = {
        enable = true;
        systemd = {
          enable = true;
          targets = [ sessionTarget ];
        };
        settings.main = {
          layer = "top";
          position = "left";
          width = 32;
          modules-left = [ "mango/workspaces" ];
          modules-center = [ "clock" ];
          modules-right = [
            "group/tray"
            "network"
            "wireplumber"
            "power-profiles-daemon"
            "battery"
            "custom/controls"
          ];
          # Dots for occupied tags, a numbered pill for the active one (CSS).
          "mango/workspaces" = {
            format = "{value}";
            hide-empty = true;
            on-click = "activate";
          };
          clock = centered // {
            format = "{:%H\n%M}";
            tooltip = false;
            on-click = popupToggle "calendar";
          };
          "group/tray" = {
            orientation = "inherit";
            drawer = {
              click-to-reveal = true;
              transition-left-to-right = false;
              empty-if-drawer-empty = true;
            };
            modules = [
              "custom/tray-chevron"
              "tray"
            ];
          };
          "custom/tray-chevron" = centered // {
            format = "󰅃";
            tooltip = false;
          };
          tray = {
            spacing = 8;
            icon-size = 16;
          };
          network = centered // {
            format-wifi = "{icon}";
            format-icons = [
              "󰤟"
              "󰤢"
              "󰤥"
              "󰤨"
            ];
            format-ethernet = "󰈀";
            format-disconnected = "󰤮";
            tooltip-format-wifi = "{essid} ({signalStrength}%)";
            tooltip-format-ethernet = "{ifname}";
            tooltip-format-disconnected = "offline";
            on-click = getExe' pkgs.networkmanagerapplet "nm-connection-editor";
          };
          wireplumber = centered // {
            format = "{icon}";
            format-muted = "󰝟";
            format-icons = [
              "󰕿"
              "󰖀"
              "󰕾"
            ];
            tooltip-format = "{node_name} {volume}%";
            on-click = getExe pkgs.pwvucontrol;
          };
          power-profiles-daemon = centered // {
            format = "{icon}";
            format-icons = {
              performance = "󰓅";
              balanced = "󰾅";
              power-saver = "󰾆";
            };
          };
          battery = centered // {
            states.warning = 15;
            format = "{icon}";
            format-charging = "󰂄";
            format-plugged = "󰚥";
            format-icons = [
              "󰂎"
              "󰁻"
              "󰁾"
              "󰂀"
              "󰁹"
            ];
            tooltip-format = "{capacity}% {timeTo}";
          };
          "custom/controls" = centered // {
            format = "󰒓";
            tooltip = false;
            on-click = popupToggle "controls";
          };
        };
        # The rail has the wallpaper's colour, so it reads as part of the frame.
        style = ''
          * { font-family: "Symbols Nerd Font Mono", sans-serif; font-size: 14px; min-height: 0; }
          window#waybar { background: #${bg}; color: #c8c5c7; border: none; }
          tooltip { background: #${card}; border: none; border-radius: 8px; }
          tooltip label { font-family: sans-serif; font-size: 12px; color: #c8c5c7; }

          #workspaces { background: transparent; margin: 10px 0; }
          #workspaces button {
            min-width: 8px;
            min-height: 8px;
            margin: 4px 12px;
            padding: 0;
            border: none;
            box-shadow: none;
            border-radius: 99px;
            background: #555555;
            color: #${bg};
          }
          #workspaces button:not(.active) label { font-size: 0; }
          #workspaces button.urgent { box-shadow: inset 0 0 0 2px #${accent}; }
          #workspaces button.active {
            min-height: 24px;
            margin: 4px 6px;
            background: #${accent};
            font-family: sans-serif;
            font-size: 11px;
            font-weight: bold;
          }

          #clock { font-family: sans-serif; font-size: 12px; font-weight: bold; padding: 6px 0; }

          #custom-tray-chevron, #tray, #network, #wireplumber,
          #power-profiles-daemon, #battery, #custom-controls {
            /* Full rail width, so every glyph centres on the same axis; the
               Mono symbol font gives each icon the same 1-em cell. */
            min-width: 32px;
            margin: 0;
            padding: 6px 0;
            font-size: 16px;
          }
          #group-tray.empty { opacity: 0; }
          /* Load the symbolic variant of tray icons, tinted with the text colour. */
          #tray { -gtk-icon-style: symbolic; }
          #wireplumber.muted, #network.disconnected { color: #888888; }
          #battery.warning.discharging { color: #${accent}; }
          #custom-controls { margin-bottom: 8px; }
        '';
      };
    };
  };
}
