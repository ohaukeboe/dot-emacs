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
  };

  config = mkIf cfg.enable {
    # It is necessary to run `sudo sbctl create-keys` first to generate
    # the secure boot keys
    #
    # To automatically decrypt a disk using TPM, run:
    # `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/<my encrypted device>`

    environment.systemPackages = with pkgs; [ sbctl ] ++ optionals cfg.tpm2Support [ tpm2-tss ];

    boot.initrd.systemd.enable = true;
    boot.loader.systemd-boot.enable = mkForce false;

    boot.lanzaboote = {
      enable = true;
      pkiBundle = cfg.pkiBundle;
    };
  };
}
