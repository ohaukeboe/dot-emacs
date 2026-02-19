{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.gaming;

  # Custom gamescope launcher with optimal settings
  gamescope-game = pkgs.writeShellScriptBin "gamescope-game" ''
    # Dynamically detect the highest current display resolution
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
      # Wayland (wlroots): Parse wlr-randr output for highest current resolution
      # Find all lines with "(current)" and extract resolution, then sort to get highest
      resolution=$(${pkgs.wlr-randr}/bin/wlr-randr | \
        ${pkgs.gnugrep}/bin/grep 'current)' | \
        ${pkgs.gnugrep}/bin/grep -oP '\d+x\d+' | \
        ${pkgs.coreutils}/bin/sort -t'x' -k1 -k2 -n -r | \
        ${pkgs.coreutils}/bin/head -1)
      width=$(echo "$resolution" | cut -d'x' -f1)
      height=$(echo "$resolution" | cut -d'x' -f2)
    else
      # X11: Use xrandr to get the primary display resolution
      resolution=$(${pkgs.xrandr}/bin/xrandr | grep -oP '(?<=current )\d+ x \d+' | head -1 | tr -d ' ')
      width=$(echo "$resolution" | cut -d'x' -f1)
      height=$(echo "$resolution" | cut -d'x' -f2)
    fi

    # Fallback if parsing failed
    if [ -z "$width" ] || [ -z "$height" ]; then
      width=1920
      height=1080
    fi

    exec ${pkgs.gamemode}/bin/gamemoderun ${pkgs.gamescope}/bin/gamescope \
      --adaptive-sync \
      -f \
      --hdr-enabled \
      -w "$width" \
      -h "$height" \
      --force-grab-cursor \
      --mouse-sensitivity 1.5 \
      -g \
      "$@"
  '';
in
{
  options.modules.gaming = {
    enable = mkEnableOption "Gaming module";
  };

  config = mkIf cfg.enable {
    # Enable Steam
    programs = {
      steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
        gamescopeSession.enable = true;
        extest.enable = true;
      };
      gamemode.enable = true;
      gamescope = {
        enable = true;
        capSysNice = false;
      };
    };

    environment.sessionVariables = {
      STEAM_FORCE_DESKTOPUI_SCALING = "1";
    };

    environment.systemPackages = with pkgs; [
      # Custom gamescope launcher
      gamescope-game

      prismlauncher

      # Lutris with extra dependencies for Wine-GE runner support
      (lutris.override {
        extraPkgs = pkgs: [
          wineWowPackages.stable
          wineWowPackages.staging
          winetricks
          wineWowPackages.waylandFull
        ];
        extraLibraries = pkgs: [
          # Additional libraries for better compatibility
          jansson
        ];
      })
      steam-run
      gamescope-wsi # HDR
    ];

    # Home-manager configuration
    home-manager.users.${config.user.username} = {
      # XDG autostart entry for Steam
      xdg.configFile."autostart/steam.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Steam
        Exec=steam -silent
        X-GNOME-Autostart-enabled=true
        NoDisplay=true
      '';
    };
  };
}
