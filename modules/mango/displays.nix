# Known display setups, applied by kanshi.
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
    sessionTarget
    lidSync
    ;

  panel = cfg.displays.internal;

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
    // optionalAttrs (o.scale != null) { scale = o.scale * 1.0; }
    // optionalAttrs (o.transform != null) { inherit (o) transform; };

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
      # A rotated display may turn portrait, which picks its layout cycle (mango-layout).
      transform = mkOption {
        type = types.nullOr (
          types.enum [
            "normal"
            "90"
            "180"
            "270"
            "flipped"
            "flipped-90"
            "flipped-180"
            "flipped-270"
          ]
        );
        default = null;
        description = "Rotation as kanshi(5) takes it; null leaves the display unrotated.";
      };
    };
  };
in
{
  options.modules.mango.displays = {
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

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.displays.setups ? undocked);
        message = ''
          modules/mango/displays.nix: modules.mango.displays.setups.undocked is
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
              modules/mango/displays.nix: modules.mango.displays.setups.${name} lists
              the same criteria twice; rename or remove the duplicate output.
            '';
          }
          {
            assertion = any (o: o.enable) s.outputs;
            message = ''
              modules/mango/displays.nix: modules.mango.displays.setups.${name} has
              no enabled output; enable at least one.
            '';
          }
        ]
      ) cfg.displays.setups
    );

    home-manager.users.${config.user.username} = {
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
    };
  };
}
