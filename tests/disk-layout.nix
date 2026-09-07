# VM test for lib/disk-layouts/luks-btrfs.nix.
#
#   nix build .#test-disk-layout -L
#
# disko's own harness formats a virtual disk with the layout, installs NixOS on
# it, reboots into the result and runs the assertions below against the running
# system. Evaluation alone cannot tell us any of this: it says nothing about
# whether the partitioning script runs, whether the LUKS mapper gets the name
# the rest of the config depends on, or whether the subvolumes end up mounted
# where they were declared.
{
  pkgs,
  diskoLib,
}:

diskoLib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "luks-btrfs-layout";

  # makeDiskoTest rewrites `device` positionally -- the first disk becomes the
  # test runner's -- so the path named here is never used. Kept as /dev/vda
  # because that is what it becomes in the booted machine.
  disko-config =
    { lib, ... }:
    lib.recursiveUpdate (import ../lib/disk-layouts/luks-btrfs.nix { device = "/dev/vda"; }) {
      # The layout carries no key material, so askPassword defaults to true and
      # formatting would block on a passphrase prompt. The harness writes this
      # file in both the installer and the booted machine.
      disko.devices.disk.main.content.partitions.luks.content.settings.keyFile = "/tmp/secret.key";
    };

  extraTestScript = ''
    # The mapper name is load-bearing: modules/sleep-then-hibernate defaults
    # boot.resumeDevice to /dev/mapper/crypted, and the machines that predate
    # disko use the same name.
    machine.succeed("cryptsetup isLuks /dev/vda2")
    machine.succeed("test -b /dev/mapper/crypted")

    # Every declared subvolume exists...
    for subvol in ["@", "@home", "@nix", "@snapshots", "@swap"]:
        machine.succeed(f"btrfs subvolume list / | grep -qs 'path {subvol}$'")

    # ...and is mounted where the layout says it should be.
    for mountpoint, subvol in [
        ("/", "@"),
        ("/home", "@home"),
        ("/nix", "@nix"),
        ("/snapshots", "@snapshots"),
        ("/swap", "@swap"),
    ]:
        machine.succeed(f"findmnt -no FSTYPE {mountpoint} | grep -qs btrfs")
        # findmnt reports the subvolume in SOURCE as /dev/mapper/crypted[/@home].
        # Matching that as a fixed string beats matching subvol= in OPTIONS,
        # where the value for "@" has no word boundary to anchor against and
        # "@" would otherwise prefix-match "@home".
        machine.succeed(f"findmnt -no SOURCE {mountpoint} | grep -qsF '[/{subvol}]'")

    # /snapshots is what machines/work-laptop/config.nix points btrbk at, and
    # /swap is where a machine enabling sleep-then-hibernate puts its swapfile.
    # Both have to be writable directories, not just mountpoints.
    machine.succeed("touch /snapshots/.probe /swap/.probe")

    # The ESP holds signed boot artifacts and must not be world-readable.
    machine.succeed("findmnt -no FSTYPE /boot | grep -qs vfat")
    machine.succeed("findmnt -no OPTIONS /boot | grep -qs fmask=0077")
  '';
}
