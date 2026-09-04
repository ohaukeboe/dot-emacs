# Shared disk layout for a single-disk machine: GPT with an ESP and a
# LUKS2-encrypted btrfs root split into subvolumes.
#
# Import it from a machine's disk.nix with the device it should own:
#
#   { imports = [ (import ../../lib/disk-layouts/luks-btrfs.nix { device = "/dev/nvme0n1"; }) ]; }
#
# Only machines provisioned with disko use this. The three machines that
# predate it keep their generated hardware-configuration.nix, whose by-uuid
# fileSystems entries would collide with the ones disko produces.
{
  device,
  # lanzaboote writes one unified kernel image per generation and
  # common/system/system.nix keeps 10 of them, so the usual 512M ESP runs out.
  espSize ? "2G",
}:

{
  disko.devices.disk.main = {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = espSize;
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            # Matches the fmask/dmask the generated configs use: the ESP holds
            # signed boot artifacts and should not be world-readable.
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };

        luks = {
          size = "100%";
          content = {
            type = "luks";
            # modules/sleep-then-hibernate defaults boot.resumeDevice to
            # /dev/mapper/crypted, and the pre-disko machines use the same
            # name. Renaming this breaks hibernation resume.
            name = "crypted";
            settings.allowDiscards = true;

            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes =
                let
                  opts = [
                    "compress=zstd"
                    "noatime"
                  ];
                in
                {
                  # @/@home naming follows the existing desktop machine.
                  "@" = {
                    mountpoint = "/";
                    mountOptions = opts;
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = opts;
                  };
                  # Separate so snapshots of / never drag the store along.
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = opts;
                  };
                  # btrbk (machines/work-laptop/config.nix) expects this to
                  # exist; systemd.tmpfiles would otherwise have to create it.
                  "@snapshots" = {
                    mountpoint = "/snapshots";
                    mountOptions = opts;
                  };
                  # Somewhere to put a hibernation swapfile that no snapshot
                  # will ever cover. A machine enabling
                  # modules.sleep-then-hibernate should point swapFile here:
                  #   modules.sleep-then-hibernate.swapFile = "/swap/swapfile";
                  # NixOS sets NoCOW on a btrfs swapfile itself, so the
                  # compress=zstd above does not apply to it.
                  "@swap" = {
                    mountpoint = "/swap";
                    mountOptions = [ "noatime" ];
                  };
                };
            };
          };
        };
      };
    };
  };
}
