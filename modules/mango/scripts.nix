# Session helper scripts for modules/mango. Kept apart from default.nix for
# size only; every script is a writeShellApplication (shellcheck at build).
{
  lib,
  pkgs,
  mango,
  panel,
  systemd,
}:

with lib;

rec {
  screenshot = pkgs.writeShellApplication {
    name = "mango-screenshot";
    runtimeInputs = with pkgs; [
      grim
      slurp
      satty
      wl-clipboard
      xdg-user-dirs
      coreutils
    ];
    text = ''
      dir="$(xdg-user-dir PICTURES)/Screenshots"
      mkdir -p "$dir"
      file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
      case "''${1:-full}" in
        full) grim "$file" ;;
        region) grim -g "$(slurp)" "$file" ;;
        annotate)
          # satty saves and copies itself; nothing to copy afterwards.
          grim -g "$(slurp)" - |
            satty --filename - --output-filename "$file" --copy-command wl-copy --early-exit
          exit 0
          ;;
        *)
          echo "usage: mango-screenshot [full|region|annotate]" >&2
          exit 2
          ;;
      esac
      wl-copy <"$file"
    '';
  };

  # Lid closed while another output is connected: turn the panel off. logind
  # already ignores the lid when docked (HandleLidSwitchDocked defaults to
  # ignore), so undocked lid close still suspends (ADR 0001).
  # `open` (lid opened) turns the panel on, then lets kanshi re-apply the
  # matched setup, which may turn it off again on purpose.
  lidSync = pkgs.writeShellApplication {
    name = "mango-lid-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.kanshi
      pkgs.wlr-randr
      mango
    ];
    text = ''
      if [ "''${1:-sync}" = open ]; then
        mmsg dispatch enable_monitor,${panel}
        kanshictl reload || true
        exit 0
      fi
      lid=""
      for f in /proc/acpi/button/lid/*/state; do
        if [ -r "$f" ]; then lid="$(cat "$f")"; fi
      done
      case "$lid" in
        *closed*) ;;
        *) exit 0 ;;
      esac
      others="$(wlr-randr --json | jq --arg p ${escapeShellArg panel} '[.[] | select(.name != $p)] | length')"
      if [ "$others" -gt 0 ]; then
        mmsg dispatch disable_monitor,${panel}
      fi
    '';
  };

  # Keyboard backlight keys: nothing in the session handles them. On ROG
  # N-KEY keyboards the asus-wmi LED (and so UPower) does not reach the
  # keyboard; asusd does. `asusctl leds next/prev` wrap, so step and clamp
  # here, and show the level in the rail's OSD (quickshell/shell.qml).
  kbdBacklight = pkgs.writeShellApplication {
    name = "mango-kbd-backlight";
    runtimeInputs = [
      pkgs.asusctl
      pkgs.quickshell
    ];
    text = ''
      levels=(off low med high)
      cur="$(asusctl leds get)"
      cur="''${cur##*: }"
      i=0
      for n in "''${!levels[@]}"; do
        if [ "''${levels[n]}" = "''${cur,,}" ]; then i=$n; fi
      done
      case "''${1:-}" in
        up) i=$((i < 3 ? i + 1 : 3)) ;;
        down) i=$((i > 0 ? i - 1 : 0)) ;;
        *)
          echo "usage: mango-kbd-backlight up|down" >&2
          exit 2
          ;;
      esac
      asusctl leds set "''${levels[i]}"
      quickshell -c mango ipc call osd keyboard "$i" 3
    '';
  };

  # Mango's reload re-enables every output that has no monitor_rule
  # (src/config/reapply.c), undoing kanshi and the lid; so re-apply both.
  reload = pkgs.writeShellApplication {
    name = "mango-reload";
    runtimeInputs = [
      pkgs.kanshi
      mango
    ];
    text = ''
      mmsg dispatch reload_config
      kanshictl reload || true
      ${getExe lidSync}
    '';
  };

  # Prints the connected displays as a displays.setups entry to paste into
  # machines/machines.nix.
  displaySetup = pkgs.writeShellApplication {
    name = "mango-display-setup";
    runtimeInputs = [
      pkgs.jq
      pkgs.wlr-randr
    ];
    text = ''
      wlr-randr --json | jq -r --arg name "''${1:-new-setup}" --arg panel ${escapeShellArg panel} '
        def crit:
          if .name == $panel then .name
          else [.make, .model, .serial] | map(select(. != null and . != "")) | join(" ")
          end;
        def mode: first(.modes[] | select(.current)) | "\(.width)x\(.height)@\(.refresh)";
        # Shift the layout so its top-left corner is 0,0: positions are unsigned.
        (map(select(.enabled) | .position) | [(map(.x) | min // 0), (map(.y) | min // 0)]) as [$minx, $miny] |
        "modules.mango.displays.setups.\($name).outputs = [",
        (.[] | "  { criteria = \(crit | tojson); enable = \(.enabled);"
          + (if .enabled then
               " mode = \(mode | tojson); position = { x = \(.position.x - $minx); y = \(.position.y - $miny); }; scale = \(.scale);"
               + (if (.transform // "normal") != "normal" then " transform = \(.transform | tojson);" else "" end)
             else "" end)
          + " }"),
        "];"'
    '';
  };

  # dmenu for the rail's Quickshell picker (quickshell/Picker.qml): lines on
  # stdin, the picked one on stdout, exit 1 on cancel, 10 on the alternate
  # pick (specs/015-picker-layouts/contracts/mango-pick.md). `--layout tiles`,
  # `sources` or `clipboard` picks a layout; anything else gets the list.
  # The screencast portal runs it as its chooser, so it names every program
  # by store path.
  pick = pkgs.writeShellApplication {
    name = "mango-pick";
    runtimeInputs = [
      pkgs.quickshell
      pkgs.coreutils
    ];
    text = ''
      layout=""
      if [[ ''${1:-} == --layout ]]; then
        layout="''${2:-}"
        shift 2 || shift
      fi
      items="$(cat)"
      dir="$(mktemp -d)"
      trap 'rm -rf "$dir"' EXIT
      mkfifo "$dir/reply"
      quickshell ipc -c mango --any-display call picker open "''${1:-Select}" "$items" "$dir/reply" "$layout" >/dev/null
      # Quickshell answers on every close; the timeout covers a shell restart.
      choice="$(timeout 300 cat "$dir/reply")" || exit 1
      [[ -n $choice ]] || exit 1
      if [[ $choice == alt$'\t'* ]]; then
        printf '%s\n' "''${choice#alt$'\t'}"
        exit 10
      fi
      printf '%s\n' "$choice"
    '';
  };

  # Locks with the Quickshell lock screen (Lock.qml) and returns once every
  # screen is covered, so swayidle's before-sleep holds the suspend until then.
  # Falls back to swaylock only when Quickshell does not answer: once it has
  # taken the lock, a second locker would be refused.
  lockScreen = pkgs.writeShellApplication {
    name = "mango-lock";
    runtimeInputs = [
      pkgs.quickshell
      pkgs.swaylock
      pkgs.coreutils
    ];
    text = ''
      ipc() { timeout 2 qs -c mango ipc call lock "$@" 2>/dev/null; }
      ipc lock >/dev/null || exec swaylock -f
      for _ in $(seq 20); do
        [[ $(ipc secure) == true ]] && exit 0
        sleep 0.1
      done
      echo "mango-lock: the lock screen is not secure yet" >&2
      exit 1
    '';
  };

  powerMenu = pkgs.writeShellApplication {
    name = "mango-power-menu";
    runtimeInputs = [
      pick
      lockScreen
      systemd
      mango
    ];
    text = ''
      # label<TAB>icon[<TAB>confirm]: the tiles picker arms confirm items first.
      choice="$(printf '%s\n' $'Lock\tlock' $'Log out\tlogout\tconfirm' $'Suspend\tsleep' \
        $'Reboot\trestart\tconfirm' $'Power off\tpower\tconfirm' |
        mango-pick --layout tiles Power)" || exit 0
      case "$choice" in
        Lock) mango-lock ;;
        'Log out') mmsg dispatch quit ;;
        Suspend) systemctl suspend ;;
        Reboot) systemctl reboot ;;
        'Power off') systemctl poweroff ;;
      esac
    '';
  };

  clipPick = pkgs.writeShellApplication {
    name = "mango-clip-pick";
    runtimeInputs = with pkgs; [
      cliphist
      coreutils
      pick
      wl-clipboard
      wtype
    ];
    # Enter (status 0) copies and pastes with Shift+Insert into the window
    # that had focus; Ctrl+Enter (10) only copies. Cancel exits before
    # wl-copy, which would otherwise empty the clipboard. The picker has
    # closed before it answers; the sleep covers focus going back.
    text = ''
      status=0
      choice="$(cliphist list | mango-pick --layout clipboard Clipboard)" || status=$?
      case "$status" in
        0 | 10) cliphist decode <<<"$choice" | wl-copy ;;
        *) exit 0 ;;
      esac
      if [[ $status == 0 ]]; then
        sleep 0.05
        wtype -M shift -k Insert -m shift
      fi
    '';
  };

  # Tiling layouts by orientation (GLOSSARY: Orientation, Layout cycle).
  # `next [MONITOR]` steps the active tag through its display's layout cycle
  # (Super+n, the rail's layout glyph). `watch` swaps a landscape layout for
  # its vertical variant on a portrait display, and back. Mango can only set
  # the focused display's active tag, so the swap happens when a tag is
  # shown on the focused display, not for hidden tags.
  layout = pkgs.writeShellApplication {
    name = "mango-layout";
    runtimeInputs = [
      pkgs.jq
      mango
    ];
    text = ''
      # Orientation and layout name of the focused display's active tag.
      current() {
        mmsg get all-monitors | jq -r --argjson names "$(names)" '
          .monitors[] | select(.active)
          | "\(if .height > .width then "portrait" else "landscape" end) \($names[.layout_symbol] // "")"'
      }
      names() { mmsg get layouts | jq -c '.layouts | map({(.symbol): .name}) | add'; }

      case "''${1:-}" in
        next)
          if [ -n "''${2:-}" ]; then mmsg dispatch "focusmon,$2"; fi
          read -r orientation layout < <(current)
          cycle=(tile scroller grid deck monocle)
          if [ "$orientation" = portrait ]; then
            cycle=(vertical_tile vertical_scroller vertical_grid vertical_deck monocle)
          fi
          target=''${cycle[0]}
          for i in "''${!cycle[@]}"; do
            if [ "''${cycle[$i]}" = "$layout" ]; then
              target=''${cycle[$(((i + 1) % ''${#cycle[@]}))]}
            fi
          done
          mmsg dispatch "setlayout,$target"
          ;;
        watch)
          # Each event prints a snapshot; ends with the session, as mmsg then fails.
          while mmsg get version >/dev/null 2>&1; do
            mmsg watch all-monitors | while read -r _; do
              read -r orientation layout < <(current)
              case "$orientation $layout" in
                "portrait tile" | "portrait scroller" | "portrait grid" | "portrait deck")
                  mmsg dispatch "setlayout,vertical_$layout"
                  ;;
                "landscape vertical_tile" | "landscape vertical_scroller" | \
                  "landscape vertical_grid" | "landscape vertical_deck")
                  mmsg dispatch "setlayout,''${layout#vertical_}"
                  ;;
              esac
            done
            sleep 1
          done
          ;;
        *)
          echo "usage: mango-layout next [MONITOR] | watch" >&2
          exit 2
          ;;
      esac
    '';
  };
}
