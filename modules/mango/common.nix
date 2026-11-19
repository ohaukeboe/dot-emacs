# Values that more than one of the mango modules needs, and the session
# helper scripts.
{
  config,
  lib,
  pkgs,
}:

with lib;

let
  cfg = config.modules.mango;

  # How far below its source the displays card parks a display that copies
  # another, in layout pixels (specs/020-duplicate-display, research R3).
  # The card, mango-copy-guard and mango-display-setup all read this value.
  parkGap = 8192;
in
rec {
  inherit parkGap;

  # Every session service is tied to this target, which mango starts itself
  # (and which the mango package ships, see systemd.packages in default.nix).
  # graphical-session.target would also start them under COSMIC.
  sessionTarget = "mango-session.target";

  # The one palette for the session (specs/013-mango-islands-shell). Frame is
  # the wallpaper and gaps, app the windows, island the bar capsules and
  # popups, raised the controls on them; fg is both text and accent.
  palette = {
    frame = "111111";
    app = "171717";
    island = "212121";
    raised = "2c2c2c";
    fg = "cabab4";
    dim = "9c918d";
    onAccent = "171717";
  };

  terminal = getExe cfg.terminal;

  # For HM modules that hardcode graphical-session.target or
  # wayland.systemd.target in their unit.
  bindToSession = {
    Unit.PartOf = mkForce [ sessionTarget ];
    Unit.After = mkForce [ sessionTarget ];
    Install.WantedBy = mkForce [ sessionTarget ];
  };
}
// import ./scripts.nix {
  inherit lib pkgs parkGap;
  mango = config.programs.mango.package;
  panel = cfg.displays.internal;
  systemd = config.systemd.package;
}
