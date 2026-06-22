# ADR 0001 — Suspend-then-hibernate via swapfile + zswap, systemd-initrd resume

**Status:** Accepted (2026-06-22)

## Context

Laptops need to survive long sleeps and flat batteries without losing state.
Hibernation requires a disk swap area sized at least as large as usable RAM.
The fleet previously had **no disk swap and no hibernation** — only `zramSwap`
(zstd, 50% RAM) configured shared in `common/system/system.nix`. zram is
RAM-backed and cannot hold a hibernation image. zswap and zram both compress
memory pages and overlap/contend when run together (zswap double-compressing
pages headed to zram).

Root on all machines is encrypted LUKS (`/dev/mapper/crypted`) + btrfs.

## Decision

1. Provide an **optional** module `modules.sleep-then-hibernate` (off by default).
2. When enabled on a machine:
   - Create a btrfs swapfile sized per-machine via `swapDevices.*.size`
     (`swapSize`, in MiB, no default — required so it's never silently undersized).
   - Enable **zswap** via `boot.kernelParams` as the compressed cache in front of
     the swapfile.
   - **Force-disable `zramSwap`** to avoid double-compression.
3. Use **systemd in initrd** (`boot.initrd.systemd.enable = true`) so resume
   locates the swapfile offset via the `HibernateLocation` EFI variable that
   systemd writes at hibernate time — no static `resume_offset` kernel param to
   compute or maintain. Set `boot.resumeDevice` to the LUKS mapper.
4. Route lid-close and idle to `suspend-then-hibernate`
   (`services.logind.settings.Login`) with `HibernateDelaySec` ≈ 45 min
   (`systemd.sleep.settings.Sleep`).

First wired on **x13-laptop** (RAM = 32 GiB → swapfile 40 GiB).

## Consequences

- (+) Declarative, per-machine opt-in; no manual offset bookkeeping.
- (+) Hibernation image encrypted at rest (swapfile lives on the LUKS volume).
- (−) Switches that machine's initrd to systemd-cryptsetup (a visible boot-flow
  change to the LUKS unlock prompt).
- (−) Consumes `swapSize` MiB of disk.
- (−) COSMIC DE may manage lid/idle via its own power daemon and override logind
  (validate post-deploy).
- (−) Reuse on btrbk machines (work-laptop) needs the swapfile excluded from
  snapshots (dedicated non-snapshotted subvolume); out of scope here.

## Alternatives rejected

- **Scripted initrd + manual `resume_offset`** — fragile; the offset changes if
  the swapfile is ever recreated or moved.
- **Keep zram alongside zswap** — redundant and contentious double-compression.
- **Swapfile only, no zswap** — ignores the zswap requirement and drops the
  compressed-cache benefit.
