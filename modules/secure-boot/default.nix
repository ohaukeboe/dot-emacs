{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.secure-boot;
in
{
  options.modules.secure-boot = {
    enable = mkEnableOption "Secure Boot using lanzaboote";

    pkiBundle = mkOption {
      type = types.str;
      default = "/var/lib/sbctl";
      description = "Path to the PKI bundle directory for Secure Boot keys";
    };

    tpm2Support = mkOption {
      type = types.bool;
      default = true;
      description = "Include TPM2 tools for automatic disk decryption";
    };

    measuredBoot = {
      enable = mkEnableOption ''
        Measured Boot via systemd-pcrlock, so a LUKS2 volume can be unlocked by
        the TPM without re-enrolling after every update.

        Binding a volume to static PCR values means re-running
        systemd-cryptenroll whenever the firmware or the Secure Boot keys
        change, because those values change with them. systemd-pcrlock binds it
        to a policy instead, and lanzaboote regenerates the measurements and
        updates the policy on every `nixos-rebuild`, so enrolment happens once.

        Off by default on purpose. systemd-pcrlock is still experimental
        upstream and this sits in the boot path, so a working machine should not
        acquire it as a side effect of a rebuild. Enrolment is a separate manual
        step -- see docs/new-machine.md
      '';

      pcrs = mkOption {
        type = types.listOf types.int;
        default = [
          0
          4
          7
        ];
        description = ''
          PCRs to lock via systemd-pcrlock. The upstream default recommendation.
          PCR 4 covers the boot chain, which is what lanzaboote actually
          controls. Adding 1, 2 or 3 is documented as possibly flaky and has to
          be tried per machine.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # Keys are generated and enrolled automatically below, so `sbctl create-keys`
    # is not needed. The firmware does have to be in Setup Mode for the
    # enrollment to succeed -- see docs/new-machine.md.

    environment.systemPackages = with pkgs; [ sbctl ] ++ optionals cfg.tpm2Support [ tpm2-tss ];

    boot.initrd.systemd.enable = true;
    boot.loader.systemd-boot.enable = mkForce false;

    # systemd-pcrlock will not build a policy for more than 8 variants, and
    # lanzaboote asserts on it. common/system/system.nix asks for 10, so lower
    # it here rather than making every machine that enables measured boot
    # remember to.
    boot.loader.systemd-boot.configurationLimit = mkIf cfg.measuredBoot.enable (mkForce 8);

    boot.lanzaboote = {
      enable = true;
      pkiBundle = cfg.pkiBundle;
      autoGenerateKeys.enable = true;
      autoEnrollKeys = {
        enable = true;
        autoReboot = true;
      };

      measuredBoot = mkIf cfg.measuredBoot.enable {
        enable = true;
        inherit (cfg.measuredBoot) pcrs;
        # autoCryptenroll is deliberately not exposed: it enrolls without a PIN,
        # and upstream is explicit that an attended workstation should require a
        # user secret in addition to the TPM.
      };
    };
  };
}
