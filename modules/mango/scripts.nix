# Session helper scripts for modules/mango. Kept apart from default.nix for
# size only; every script is a writeShellApplication (shellcheck at build).
{
  lib,
  pkgs,
  mango,
  panel,
  parkGap,
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
  # `state` only prints `open` or `closed` (`open` on a machine with no
  # lid), for the displays card (specs/020-duplicate-display).
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
      lid_state() {
        local lid="" f
        for f in /proc/acpi/button/lid/*/state; do
          if [ -r "$f" ]; then lid="$(cat "$f")"; fi
        done
        case "$lid" in
          *closed*) echo closed ;;
          *) echo open ;;
        esac
      }
      if [ "''${1:-sync}" = state ]; then
        lid_state
        exit 0
      fi
      if [ "''${1:-sync}" = open ]; then
        mmsg dispatch enable_monitor,${panel}
        kanshictl reload || true
        exit 0
      fi
      [ "$(lid_state)" = closed ] || exit 0
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

  # Swaps the visible windows of the focused monitor and the next one, each
  # onto the other monitor's current tag; focus and cursor follow the focused
  # window.
  swapMonitors = pkgs.writeShellApplication {
    name = "mango-swap-monitors";
    runtimeInputs = [
      pkgs.jq
      mango
    ];
    text = ''
      active() { mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .name'; }
      visible() { mmsg get all-clients | jq -r --arg m "$1" '.clients[] | select(.monitor == $m and .is_visible) | .id'; }
      focused=$(mmsg get focusing-client | jq -r '.id // empty')
      # focusmon,next skips disabled outputs, which all-monitors still lists.
      a=$(active)
      mmsg dispatch focusmon,next
      b=$(active)
      [ "$a" != "$b" ] || exit 0
      from_a=$(visible "$a")
      from_b=$(visible "$b")
      for id in $from_a; do mmsg dispatch "tagmon,$b,0" "client,$id"; done
      for id in $from_b; do mmsg dispatch "tagmon,$a,0" "client,$id"; done
      # focusid leaves the cursor behind and focusmon (which warps it) is a
      # no-op on the selected monitor, so step to $a first.
      mmsg dispatch "focusmon,$a"
      mmsg dispatch "focusmon,$b" ''${focused:+"client,$focused"}
    '';
  };

  # Keeps focus and windows off a display that copies another
  # (specs/020-duplicate-display, research R5). The displays card parks a
  # copy where the pointer cannot go, but focusmon and tagmon still reach
  # it. Runs while a copy exists, with COPY=SOURCE for each:
  # a window on a copy goes to its source; a focused copy passes focus on to
  # the next display that is not a copy, in the direction it came from.
  copyGuard = pkgs.writeShellApplication {
    name = "mango-copy-guard";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      mango
    ];
    text = ''
      usage() {
        echo "usage: mango-copy-guard COPY=SOURCE [COPY=SOURCE ...]" >&2
        exit 2
      }
      [ "$#" -gt 0 ] || usage
      declare -A source_of
      for pair in "$@"; do
        case "$pair" in
          ?*=?*) source_of["''${pair%%=*}"]="''${pair#*=}" ;;
          *) usage ;;
        esac
      done

      # The last focused display that is not a copy: where focus came from.
      last=""
      sweep() {
        local monitors active id monitor names n i from to forward step target
        while read -r id monitor; do
          if [ -n "''${source_of[$monitor]:-}" ]; then
            mmsg dispatch "tagmon,''${source_of[$monitor]},0" "client,$id"
          fi
        done < <(mmsg get all-clients | jq -r '.clients[] | "\(.id) \(.monitor)"')
        monitors=$(mmsg get all-monitors)
        active=$(jq -r 'first(.monitors[] | select(.active) | .name) // empty' <<<"$monitors")
        [ -n "$active" ] || return 0
        if [ -z "''${source_of[$active]:-}" ]; then
          last=$active
          return 0
        fi
        # Displays that are off are listed with no size; focusmon skips them.
        mapfile -t names < <(jq -r '.monitors[] | select(.width > 0) | .name' <<<"$monitors")
        n=''${#names[@]}
        from=-1
        to=-1
        for i in "''${!names[@]}"; do
          if [ "''${names[$i]}" = "$last" ]; then from=$i; fi
          if [ "''${names[$i]}" = "$active" ]; then to=$i; fi
        done
        target=''${source_of[$active]}
        if [ "$from" -ge 0 ] && [ "$to" -ge 0 ]; then
          forward=$(((to - from + n) % n))
          step=1
          if [ "$forward" -gt $((n - forward)) ]; then step=-1; fi
          i=$to
          for _ in "''${names[@]}"; do
            i=$(((i + step + n) % n))
            if [ -z "''${source_of[''${names[$i]}]:-}" ]; then
              target=''${names[$i]}
              break
            fi
          done
        fi
        mmsg dispatch "focusmon,$target"
      }

      dir=$(mktemp -d)
      mkfifo "$dir/events"
      mmsg watch all-monitors >"$dir/events" &
      a=$!
      mmsg watch all-clients >"$dir/events" &
      b=$!
      trap 'kill "$a" "$b" 2>/dev/null || true; rm -rf "$dir"' EXIT
      trap 'exit 0' TERM INT
      exec 3<"$dir/events"
      sweep
      # Ends with the shell that started it, also when that one was killed.
      while kill -0 "$PPID" 2>/dev/null; do
        status=0
        read -r -t 5 _ <&3 || status=$?
        if [ "$status" -eq 0 ]; then
          # One sweep answers a burst of events.
          while read -r -t 0.05 _ <&3; do :; done
          sweep
        elif [ "$status" -le 128 ]; then
          # Not a timeout: the watchers ended, and so has the session.
          break
        fi
      done
    '';
  };

  # Prints the connected displays as a displays.setups entry to paste into
  # machines/machines.nix. `--copy` puts it on the clipboard instead, for the
  # displays card (quickshell/Displays.qml). A display parked as a copy
  # (specs/020-duplicate-display) is written as an extended one, right of the
  # others: a setup cannot describe a duplicate.
  displaySetup = pkgs.writeShellApplication {
    name = "mango-display-setup";
    runtimeInputs = [
      pkgs.jq
      pkgs.wl-clipboard
      pkgs.wlr-randr
    ];
    text = ''
      copy=""
      if [ "''${1:-}" = --copy ]; then
        copy=1
        shift
      fi
      entry="$(wlr-randr --json | jq -r --arg name "''${1:-new-setup}" --arg panel ${escapeShellArg panel} --argjson gap ${toString parkGap} '
        def crit:
          if .name == $panel then .name
          else [.make, .model, .serial] | map(select(. != null and . != "")) | join(" ")
          end;
        def mode: first(.modes[] | select(.current)) | "\(.width)x\(.height)@\(.refresh)";
        def width:
          first(.modes[] | select(.current)) as $m
          | (if (.transform // "normal") | test("90$|270$") then $m.height else $m.width end) / .scale | floor;
        # A copy is parked a gap or more below its source.
        (map(select(.enabled and .position.y < $gap) | .position.x + width) | max // 0) as $right |
        reduce .[] as $o ({ out: [], x: $right };
          if $o.enabled and $o.position.y >= $gap
          then .x as $x | .out += [$o | .position = { x: $x, y: 0 }] | .x += ($o | width)
          else .out += [$o] end) | .out |
        # Shift the layout so its top-left corner is 0,0: positions are unsigned.
        (map(select(.enabled) | .position) | [(map(.x) | min // 0), (map(.y) | min // 0)]) as [$minx, $miny] |
        "modules.mango.displays.setups.\($name).outputs = [",
        (.[] | "  { criteria = \(crit | tojson); enable = \(.enabled);"
          + (if .enabled then
               " mode = \(mode | tojson); position = { x = \(.position.x - $minx); y = \(.position.y - $miny); }; scale = \(.scale);"
               + (if (.transform // "normal") != "normal" then " transform = \(.transform | tojson);" else "" end)
             else "" end)
          + " }"),
        "];"')"
      if [ -n "$copy" ]; then
        # Typed: wl-copy would guess application/x-ruby from the leading
        # "module" and offer no text type, so Emacs could not paste it.
        printf '%s\n' "$entry" | wl-copy --type text/plain
      else
        printf '%s\n' "$entry"
      fi
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
        0 | 10)
          # Text is typed: wl-copy guesses from the content, and a guess such
          # as application/x-ruby (text starting with "module") comes with no
          # text type, which Emacs cannot paste. Images keep the guess.
          type=(--type text/plain)
          [[ $choice =~ ^[0-9]+$'\t'"[[ binary data " ]] && type=()
          cliphist decode <<<"$choice" | wl-copy "''${type[@]}"
          ;;
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
