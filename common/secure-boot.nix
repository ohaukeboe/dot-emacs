{ pkgs, lib, ... }:

# It is necessary to run `sudo sbctl create-keys` first to generate
# the secure boot keys
#
# To automatically decrypt a disk using TPM, run:
# `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/<my encrypted device>`
{
  environment.systemPackages = with pkgs; [
    sbctl
    tpm2-tss
  ];

  boot.initrd.systemd.enable = true;
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
