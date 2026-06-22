# Glossary

Shared vocabulary for this config. Keep terms short and link decisions to the
relevant ADR under `docs/adr/`.

## Sleep / hibernation (see ADR 0001)

- **suspend-then-hibernate** — systemd sleep mode: suspend to RAM first, then
  automatically hibernate after `HibernateDelaySec` (or on critical battery).
- **hibernate (S4)** — write RAM contents to disk swap and power off; restore on
  next boot.
- **suspend (S3)** — keep RAM powered, everything else off; fast resume, but
  drains battery and loses state if power is lost.
- **swapfile** — a regular file used as swap space; here it is the
  hibernation-image target. Created declaratively via `swapDevices.*.size`.
- **zswap** — kernel compressed *cache* sitting in front of a real (disk) swap
  device; pages fall through to the swapfile when the pool is full. Configured
  via `zswap.*` kernel parameters.
- **zram** — a compressed *block device* used directly as swap (RAM-backed).
  Disabled on machines using `sleep-then-hibernate` to avoid overlapping with
  zswap.
- **resume_offset / HibernateLocation** — the block offset of the hibernation
  image within the swapfile. With systemd in initrd, recorded automatically in
  the `HibernateLocation` EFI variable instead of a static kernel parameter.
- **NoCOW (`chattr +C`)** — btrfs attribute disabling copy-on-write; required for
  swapfiles on btrfs. NixOS sets it automatically when creating a swapfile via
  `swapDevices.*.size`.
