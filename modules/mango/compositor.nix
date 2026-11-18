# Mango's own config file: input, theming, autostart and key bindings.
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
    terminal
    lockScreen
    screenshot
    lidSync
    layout
    kbdBacklight
    reload
    powerMenu
    clipPick
    ;

  # The OSD's IPC target in the rail's Quickshell config (shell.qml).
  osd = "${getExe pkgs.quickshell} -c mango ipc call osd";
  playerctl = getExe pkgs.playerctl;
  # A script so spawn needs no shell quoting. my/ghostel-frame (config.org)
  # opens a new ghostel buffer that closes together with the frame.
  hm = config.home-manager.users.${config.user.username};
  emacs = hm.programs.emacs.finalPackage;
  ghostelFrame = pkgs.writeShellScript "ghostel-frame" ''
    exec ${emacs}/bin/emacsclient -c -a "" -e "(my/ghostel-frame)"
  '';

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
    # Clickfinger: a two-finger click anywhere is a right click.
    "trackpad_click_method=2"

    # The COSMIC module sets QT_QPA_PLATFORMTHEME=cosmic system-wide.
    "env=QT_QPA_PLATFORMTHEME,gtk3"
    # Theming lives here, not in COSMIC, so COSMIC can be turned off.
    "env=GTK_THEME,adw-gtk3-dark"
    "env=XCURSOR_THEME,Adwaita"
    "env=XCURSOR_SIZE,24"
    "cursor_theme=Adwaita"
    "cursor_size=24"
    "border_radius=18"
    "border_px=2"
    # App-coloured, so a border only shows on the focused window.
    "border_color=0x${palette.app}ff"
    "focus_color=0x${palette.fg}ff"
    "gap_inner_horizontal=12"
    "gap_inner_vertical=12"
    "gap_outer_horizontal=12"
    "gap_outer_vertical=12"
    # Deck tabs and window-group tabs, drawn like the rail's capsules
    # (Quickshell Config.qml): island capsules with dim text, the focused tab
    # filled with fg; railItem tall, fontLabel DemiBold. Mango packs tabs edge
    # to edge on the window, so a transparent 3 px border spaces them: 34 px
    # bars hold 28 px capsules.
    "tab_bar_height=34"
    "group_bar_height=34"
    "new_is_master=0"
  ]
  ++
    concatMap
      (bar: [
        "${bar}_decorate_font_desc=sans-serif DemiBold 14px"
        "${bar}_decorate_bg_color=0x${palette.island}ff"
        "${bar}_decorate_fg_color=0x${palette.dim}ff"
        "${bar}_decorate_focus_bg_color=0x${palette.fg}ff"
        "${bar}_decorate_focus_fg_color=0x${palette.onAccent}ff"
        "${bar}_decorate_border_width=3"
        "${bar}_decorate_border_color=0x00000000"
        "${bar}_decorate_corner_radius=14"
        "${bar}_decorate_padding_x=12"
      ])
      [
        "tab_bar"
        "group_bar"
      ]
  ++ [

    # Reloading resets outputs; Super+r runs mango-reload instead.
    "auto_reload_config=0"
    # No monitor_rule on purpose: unknown displays get Mango's auto placement
    # (right of the others); known setups are kanshi profiles.

    "exec_once=${getExe pkgs.swaybg} -c '#${palette.frame}'"
    "exec_once=${getExe lidSync}"
    # Not a systemd unit: mmsg needs MANGO_INSTANCE_SIGNATURE, which only
    # Mango's own children inherit.
    "exec_once=${getExe layout} watch"
    # The browser on tag 1 and Emacs on tag 2 at login. window_rule_once
    # moves only the first matching window, so later Emacs frames
    # (Super+Return) and browser windows open on the current tag.
    "window_rule_once=tags:1,app_id:^zen-beta$"
    "window_rule_once=tags:2,app_id:^emacs$"
    "exec_once=${getExe hm.programs.zen-browser.finalPackage}"
    "exec_once=${getExe emacs}"
    "switchbind=fold,spawn,${getExe lidSync}"
    "switchbind=unfold,spawn,${getExe lidSync} open"

    "bind=SUPER,r,spawn,${getExe reload}"
    "bind=SUPER+SHIFT,Escape,spawn,${getExe powerMenu}"
    "bind=CTRL,Print,spawn,${getExe screenshot} annotate"
    "bind=SUPER,Return,spawn,${ghostelFrame}"
    "bind=SUPER+CTRL,Return,spawn,${terminal}"
    # Swaps the focused window with the master; new windows open in the stack.
    "bind=SUPER+SHIFT,Return,zoom,"
    "bind=SUPER,d,spawn,${getExe pkgs.quickshell} -c mango ipc call launcher toggle"
    "bind=SUPER,q,killclient,"
    "bind=SUPER,Tab,focusstack,next"
    "bind=SUPER+SHIFT,Tab,focusstack,prev"
    "bind=SUPER,f,togglefullscreen,"
    "bind=SUPER+SHIFT,f,togglefloating,"
    # Steps the tag through its display's layout cycle (mango-layout).
    "bind=SUPER,n,spawn,${getExe layout} next"
    "bind=SUPER,Escape,spawn,${getExe lockScreen}"
    "bind=SUPER,v,spawn,${getExe clipPick}"
    "bind=NONE,Print,spawn,${getExe screenshot} full"
    "bind=SHIFT,Print,spawn,${getExe screenshot} region"
    # The laptop's Fn+F6 screenshot key sends Super+Shift+S, not Print.
    "bind=SUPER+SHIFT,s,spawn,${getExe screenshot} region"
    # Ctrl+Fn+F6: the whole display, since the laptop has no Print key.
    "bind=SUPER+CTRL+SHIFT,s,spawn,${getExe screenshot} full"
    "bind=SUPER,space,spawn,${protonPass}"
    "bind=SUPER+SHIFT,space,spawn,${onePassword}"

    "bindl=NONE,XF86AudioRaiseVolume,spawn,${osd} volumeUp"
    "bindl=NONE,XF86AudioLowerVolume,spawn,${osd} volumeDown"
    "bindl=NONE,XF86AudioMute,spawn,${osd} mute"
    "bindl=NONE,XF86AudioMicMute,spawn,${osd} micMute"
    "bindl=NONE,XF86MonBrightnessUp,spawn,${osd} brightnessUp"
    "bindl=NONE,XF86MonBrightnessDown,spawn,${osd} brightnessDown"
    "bindl=NONE,XF86KbdBrightnessUp,spawn,${getExe kbdBacklight} up"
    "bindl=NONE,XF86KbdBrightnessDown,spawn,${getExe kbdBacklight} down"
    "bindl=NONE,XF86AudioPlay,spawn,${playerctl} play-pause"
    "bindl=NONE,XF86AudioNext,spawn,${playerctl} next"
    "bindl=NONE,XF86AudioPrev,spawn,${playerctl} previous"

    "mousebind=SUPER,btn_left,moveresize,curmove"
    "mousebind=SUPER,btn_right,moveresize,curresize"
  ]
  ++ concatLists (
    mapAttrsToList
      (key: dir: [
        "bind=SUPER,${key},focusdir,${dir}"
        "bind=SUPER+SHIFT,${key},move_client,${dir}"
      ])
      {
        Left = "left";
        Right = "right";
        Up = "up";
        Down = "down";
        h = "left";
        l = "right";
        k = "up";
        j = "down";
      }
  )
  ++ concatMap (
    n:
    let
      i = toString n;
    in
    [
      "bind=SUPER,${i},view,${i},0"
      "bind=SUPER+SHIFT,${i},tag,${i},0"
      # Add or remove tag i: from the view, or from the focused window.
      "bind=SUPER+CTRL,${i},toggleview,${i}"
      "bind=SUPER+ALT,${i},toggletag,${i}"
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
in
{
  config = mkIf cfg.enable {
    home-manager.users.${config.user.username} = {
      xdg.configFile."mango/config.conf" = {
        source = mangoConfig;
        # auto_reload_config is off, so reload on rebuild through mango-reload.
        # Activation runs outside the session; Mango imports WAYLAND_DISPLAY
        # into the systemd user environment before starting the target.
        onChange = ''
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          if ${config.systemd.package}/bin/systemctl --user -q is-active ${sessionTarget}; then
            eval "$(${config.systemd.package}/bin/systemctl --user show-environment \
              | grep -E '^WAYLAND_DISPLAY=' | sed 's/^/export /')"
            # mmsg finds Mango through this, which Mango does not export to systemd.
            sock="$(ls -t "$XDG_RUNTIME_DIR"/mango-*.sock 2>/dev/null | head -n1)" || true
            if [ -n "$sock" ]; then export MANGO_INSTANCE_SIGNATURE="$sock"; fi
            ${getExe reload} || echo "mango-reload failed" >&2
          fi
        '';
      };
    };
  };
}
