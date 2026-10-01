# Partitioning for dig. Applied by disko at install time, and from then on
# the source of every fileSystems entry for this machine.
{
  imports = [
    (import ../../lib/disk-layouts/luks-btrfs.nix { device = "/dev/nvme0n1"; })
  ];
}
