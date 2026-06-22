{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.modules.sleep-then-hibernate;
in
{
  options.modules.sleep-then-hibernate = {
    enable = mkEnableOption "suspend-then-hibernate via swapfile + zswap";

    swapSize = mkOption {
      type = types.ints.positive; # MiB; no default → required when enabled
      example = 40960;
      description = ''
        Swapfile size in MiB. Must be >= usable RAM for hibernation to fit the
        image. No default: set it per-machine based on that machine's RAM.
      '';
    };

    swapFile = mkOption {
      type = types.str;
      default = "/swapfile";
      description = ''
        Path of the swapfile. On btrfs it must live on a NoCOW location; NixOS
        sets NoCOW automatically when creating a swapfile via `size`.
      '';
    };

    resumeDevice = mkOption {
      type = types.str;
      default = "/dev/mapper/crypted";
      description = ''
        Block device holding the swapfile's filesystem (the unlocked LUKS
        mapper). Used as `boot.resumeDevice`.
      '';
    };

    hibernateDelay = mkOption {
      type = types.str;
      default = "45min";
      description = "systemd HibernateDelaySec — how long to stay suspended before hibernating.";
    };

    idleActionSec = mkOption {
      type = types.str;
      default = "30min";
      description = "logind IdleActionSec — idle time before triggering suspend-then-hibernate.";
    };

    zswap = {
      maxPoolPercent = mkOption {
        type = types.ints.between 1 100;
        default = 20;
        description = "zswap pool size as a percentage of RAM (zswap.max_pool_percent).";
      };
      compressor = mkOption {
        type = types.str;
        default = "zstd";
        description = "zswap compression algorithm (zswap.compressor).";
      };
      zpool = mkOption {
        type = types.str;
        default = "zsmalloc";
        description = "zswap allocator (zswap.zpool).";
      };
    };
  };

  config = mkIf cfg.enable {
    # Avoid double-compression: zswap supersedes zram on this machine.
    zramSwap.enable = mkForce false;

    # Compressed cache in front of the disk swapfile.
    boot.kernelParams = [
      "zswap.enabled=1"
      "zswap.compressor=${cfg.zswap.compressor}"
      "zswap.zpool=${cfg.zswap.zpool}"
      "zswap.max_pool_percent=${toString cfg.zswap.maxPoolPercent}"
    ];

    # NixOS auto-creates the swapfile and sets NoCOW on btrfs.
    swapDevices = [
      {
        device = cfg.swapFile;
        size = cfg.swapSize;
      }
    ];

    # Resume: systemd in initrd records the swapfile offset in the
    # HibernateLocation EFI variable on hibernate, so no static resume_offset
    # kernel param is needed.
    boot.initrd.systemd.enable = true;
    boot.resumeDevice = cfg.resumeDevice;

    # Trigger policy: lid-close and idle fall through to hibernate after the delay.
    systemd.sleep.settings.Sleep.HibernateDelaySec = cfg.hibernateDelay;
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
      IdleAction = "suspend-then-hibernate";
      IdleActionSec = cfg.idleActionSec;
    };
  };
}
