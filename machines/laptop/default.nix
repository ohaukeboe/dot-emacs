{ lib, pkgs, ... }:

{
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
  ];

  # The zen kernel breaks amdgpu (Renoir) on hibernate resume: every compute
  # ring fails ("IB test failed on comp_1.x.x (-110)") and the desktop freezes.
  # Stock 7.2.7 resumes cleanly, so this machine stays off zen.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
}
