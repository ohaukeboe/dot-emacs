{ lib, ... }:

with lib;

{
  options = {
    user = {
      username = mkOption {
        type = types.str;
        default = "oskar";
        description = "Primary username for the system";
        example = "alice";
      };

      # Example of additional options you can add later:
      # email = mkOption {
      #   type = types.str;
      #   default = "";
      #   description = "User's email address";
      # };
      #
      # fullName = mkOption {
      #   type = types.str;
      #   default = "";
      #   description = "User's full name";
      # };
    };

    system = {
      audio.allowedSampleRates = mkOption {
        type = types.nullOr (types.listOf types.int);
        default = null;
        description = ''
          List of allowed sample rates for PipeWire audio.
          These values should match the capabilities of your audio hardware.
          Common values: 44100 (CD quality), 48000 (professional), 96000, 192000 (high-res).
          Set to null to disable custom sample rate configuration.
          To check what sample rates your DAC supports, run
          `grep -E 'Codec|Audio Output|rates' /proc/asound/card*/codec#*`
        '';
        example = [
          44100
          48000
          96000
        ];
      };
    };

  };
}
