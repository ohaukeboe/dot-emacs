{ pkgs, lib, ... }:

# It is necessary to run `sudo sbctl create-keys` first to generate
# the secure boot keys
{
  environment.systemPackages = [
    pkgs.sbctl
  ];

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
