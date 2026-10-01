{ ... }:

{
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
  ];

  # The BIOS shipped in 2023 (N3QET37W 1.37); Lenovo publishes updates via LVFS.
  services.fwupd.enable = true;

  # dig has hard-crashed with nothing in the journal or pstore. Turn lockups
  # into panics so efi_pstore keeps the kernel log, then reboot after 10s.
  boot.kernel.sysctl = {
    "kernel.softlockup_panic" = 1;
    "kernel.hardlockup_panic" = 1;
    "kernel.panic" = 10;
  };
}
