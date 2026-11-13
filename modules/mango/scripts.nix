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
        "modules.mango.displays.setups.\($name).outputs = [",
        (.[] | "  { criteria = \(crit | tojson); enable = \(.enabled);"
          + (if .enabled then
               " mode = \(mode | tojson); position = { x = \(.position.x); y = \(.position.y); }; scale = \(.scale);"
             else "" end)
          + " }"),
        "];"'
    '';
  };

  powerMenu = pkgs.writeShellApplication {
    name = "mango-power-menu";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.swaylock
      systemd
      mango
    ];
    text = ''
      choice="$(printf '%s\n' lock logout suspend reboot poweroff | fuzzel --dmenu --prompt 'power> ')" || exit 0
      case "$choice" in
        lock) swaylock -f ;;
        logout) mmsg dispatch quit ;;
        suspend) systemctl suspend ;;
        reboot) systemctl reboot ;;
        poweroff) systemctl poweroff ;;
      esac
    '';
  };

  clipPick = pkgs.writeShellApplication {
    name = "mango-clip-pick";
    runtimeInputs = with pkgs; [
      cliphist
      fuzzel
      wl-clipboard
    ];
    text = "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy";
  };
}
