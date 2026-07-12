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

    sops = {
      ageKey = mkOption {
        type = types.enum [
          "default"
          "tpm"
          "yubikey-wallet"
          "yubikey-home"
        ];
        default = "default";
        description = ''
          Which age key type to use for SOPS decryption.
          Each context resolves this to its own directory:
            NixOS system:  /var/lib/sops-nix/<key>.txt  (default -> keys.txt)
            Home Manager:  ~/.config/sops/age/<key>.txt  (default -> keys.txt)
          Note: "tpm" is only functional on NixOS/Linux with a TPM.
        '';
      };
    };

    system = {
      audio.echoCancel.enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable system-wide acoustic echo cancellation (AEC) via PipeWire's
          libpipewire-module-echo-cancel with the WebRTC backend.

          Uses monitor.mode so all speaker output is used as the cancellation
          reference and removed from the microphone, letting you use speakers
          during online calls. Select the "Echo Cancellation Source" device as
          your microphone in call apps.

          Follows the default sink across device swaps. If it misbehaves with a
          particular Bluetooth headset, set this to false for that host.
          See docs/aec-research.md for details.
        '';
      };

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
