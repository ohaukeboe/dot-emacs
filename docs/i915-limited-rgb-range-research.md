# Washed-out colours on DP MST at 4K 120 Hz: i915 limited RGB range

Research report. Question: why does the Samsung Odyssey G80SD show grey
blacks and washed-out colours on `dig-laptop` at some 4K modes, and what are
the options to fix it declaratively?

Verified on 2026-10-27 against the running system and these sources:

- Linux `v7.2` (`torvalds/linux`); the running kernel is `7.2.11-zen1`.
- cosmic-comp `epoch-1.10.0`. It pins Smithay at `e3d461a`
  ([Cargo.toml L149](https://github.com/pop-os/cosmic-comp/blob/epoch-1.10.0/Cargo.toml#L149)).
- KWin `81fb006` and mutter `2b9c078`, through their GitHub mirrors.
- nixpkgs `02c087f`, the root `nixpkgs` input (`nixpkgs_6` in `flake.lock`).
  It matches `/run/current-system/nixos-version` `26.11.20261020.02c087f`.

## TL;DR

On **Automatic**, i915 sends limited-range RGB (16–235) on DP and DP MST for
any mode whose timing matches a CTA-861 VIC other than VIC 1. It does not
check what kind of sink is attached or whether the sink can select its range. The G80SD
advertises 4K60 and 4K120 as VIC 97 and VIC 118. Its preferred 4K 59.997 Hz
mode is its own DTD timing, and CTA-861 defines no 2560x1440 VIC, so those
modes get full range. cosmic-comp never sets `Broadcast RGB`, and Smithay offers no API for
it. While COSMIC holds DRM master, no other program can set it.

## Observations (live session)

- Host `dig-laptop`: Intel iGPU, `i915`, `7.2.11-zen1`, COSMIC on Wayland,
  cosmic-comp 1.10.0 (`/nix/store/8h46z7yp…-cosmic-comp-1.10.0`). The kernel
  comes from `boot.kernelPackages = pkgs.linuxPackages_zen` in
  `common/system/system.nix:18`. COSMIC comes from `modules.cosmic-de.enable`
  in `machines/machines.nix`. `machines/dig-laptop/` holds only disk and
  hardware config, and nothing about the display.
- Monitor G80SD on MST connector `DP-9` through a Lenovo TB5 Smart Dock 7500
  on a TB4 port. A second monitor is on `DP-7`. A KVM shares the monitor with a desktop
  PC, which shows correct colours.
- Bad: 3840x2160 @ 120.000, 119.880 and 60.000 Hz. Good: 3840x2160 @ 59.997
  Hz (preferred) and 2560x1440 @ 60, 120 and 240 Hz, every 1440p rate
  COSMIC Settings offers. Settings rounds rates: its 1440p 120 Hz is the
  119.998 Hz mode that `cosmic-randr list` shows.
- With `drm.debug=0x4`, 4K120 shows `output format: RGB, sink format: RGB`,
  `pipe bpp: 24` and DSC (17.0 bpp, 4 slices, 2 streams). So the cause is
  neither bandwidth nor YCbCr 4:2:0.
- `edid-decode /sys/class/drm/card1-DP-9/edid` (run in this research):
  - DTD 1 is 3840x2160 59.996625 Hz at 533.25 MHz.
  - The CTA Video Data Block lists VIC 97 (4K60, 594 MHz) and VIC 118
    (4K120, 1188 MHz).
  - DTD 3 is 2560x1440 119.997589 Hz.
  - **No** Video Capability Data Block (so QS = 0) and **no** HDMI VSDB.
  - A DisplayID 2.0 Type X (formula) block with a CVT-RB 3840x2160
    239.990737 Hz timing.

## 1. The i915 code path (verified)

- Both SST and MST compute the range with the same function.
  [`intel_dp_compute_config`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_dp.c#L3693-L3694)
  and the MST
  [`mst_stream_compute_config`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_dp_mst.c#L749-L750)
  both call `intel_dp_limited_color_range()`.
- [`intel_dp_limited_color_range`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_dp.c#L3073-L3104)
  works like this:
  - It returns false for non-RGB output.
  - On `INTEL_BROADCAST_RGB_AUTO` it returns
    `pipe_bpp != 18 && drm_default_rgb_quant_range(mode) == LIMITED`.
  - Otherwise it returns `broadcast_rgb == LIMITED`.
  - It consults nothing about the sink: not QS, not `is_hdmi`.
- [`drm_default_rgb_quant_range`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L6033-L6040)
  returns limited for `drm_match_cea_mode(mode) > 1`.
- The limited range is signalled to the sink in two places:
  - the MSA MISC bit `DP_MSA_MISC_COLOR_CEA_RGB`
    ([intel_ddi.c L456-L457](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_ddi.c#L456-L457));
  - the VSC SDP `dynamic_range`
    ([intel_dp.c L3201-L3203](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_dp.c#L3201-L3203)).

  The G80SD evidently displays the 16–235 signal as full range, but
  *unverified* whether it reads either of these fields.
- **The property is still driver-private in i915.**
  - i915 creates its own `Broadcast RGB` enum (Automatic / Full /
    Limited 16:235), with initial value 0 = Automatic
    ([intel_connector.c L274-L297](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_connector.c#L274-L297)).
  - It attaches the property to SST DP in
    [`intel_dp_add_properties`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_dp.c#L7169)
    and to MST connectors in
    [`mst_topology_add_connector_properties`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_dp_mst.c#L1691).
  - It stores the value in `intel_digital_connector_state`
    ([intel_atomic.c L69-L70, L104-L106](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_atomic.c#L104-L106)).
- The DRM-core
  [`drm_connector_attach_broadcast_rgb_property`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_connector.c#L2894-L2916)
  with `DRM_HDMI_BROADCAST_RGB_*`
  ([drm_connector.h L385-L401](https://github.com/torvalds/linux/blob/v7.2/include/drm/drm_connector.h#L385-L401))
  belongs to the HDMI state helper, which i915 does not use. That helper's
  [`hdmi_is_limited_range`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/display/drm_hdmi_state_helper.c#L370-L395)
  returns **full** on Automatic when the sink is not HDMI
  (`if (!info->is_hdmi) return false;`, L391). This is upstream prior art for
  fix A.
- **QS is ignored on DP, and is absent here anyway.**
  - [`drm_parse_vcdb`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L6129-L6138) sets
    `rgb_quant_range_selectable`.
  - Only the HDMI AVI-infoframe helper
    [`drm_hdmi_avi_infoframe_quant_range`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L7444-L7463)
    reads it.
  - The G80SD has no VCDB, so QS would be 0 even if i915 consulted it.
- The CTA-861 rule itself ("all CEA modes other than VIC 1 use limited") is
  cited in kernel comments only. The CTA-861 text is paywalled: *unverified*
  first-hand.

## 2. Which VICs, and the 1000/1001 rates (verified)

| Mode                      | Clock (MHz)    | Match           | Range   |
|---------------------------|----------------|-----------------|---------|
| 3840x2160 @ 60.000        | 594.000        | VIC 97          | limited |
| 3840x2160 @ 120.000       | 1188.000       | VIC 118         | limited |
| 3840x2160 @ 119.880       | 1186.813       | VIC 118 (alt)   | limited |
| 3840x2160 @ 59.997        | 533.250 (DTD1) | none            | full    |
| 2560x1440 @ 60/120/240    | various        | none (no VIC)   | full    |
| 3840x2160 @ 239.99 (CVT)  | 2331.750       | none            | full    |

- The VIC 97 and VIC 118 timings are 4400x2250 totals
  ([drm_edid.c L1292-L1296, L1397-L1401](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L1292-L1401)).
- [`drm_match_cea_mode`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L4388-L4419) checks
  each VIC at its listed clock and at
  [`cea_mode_alternate_clock`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L4291-L4309):
  - The alternate clock is `clock * 1000 / 1001` when vrefresh % 6 == 0 and
    vdisplay is not 240 or 480.
  - Clocks are compared with `KHZ2PICOS` equality, then timings and flags
    with `drm_mode_match`.
  - Hence 119.88 Hz matches VIC 118.
- The 4K 239.99 Hz row is inferred: the kernel adds DisplayID Type IX and
  Type X formula timings
  ([`add_displayid_formula_modes`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L6962-L6992)),
  and a CVT-RB timing cannot match a CTA VIC. *Unverified* that COSMIC lists
  this mode, and that the dock or MST link can carry it.

## 3. Missing `i915_dsc_fec_support` (verified)

[`intel_connector_debugfs_add`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_display_debugfs.c#L1346-L1361)
creates the `i915_dsc_*` files only for eDP or for
`DRM_MODE_CONNECTOR_DisplayPort && !connector->mst.dp`. An MST connector has
`mst.dp` set, so the file is absent by design. Its absence does not mean DSC
is off.

## 4. cosmic-comp and Smithay (verified)

- No `Broadcast RGB` code exists in either project:
  - in the cosmic-comp 1.10.0 tree (grep of a checkout);
  - in GitHub code search of `pop-os/cosmic-comp` and `Smithay/smithay`.
- cosmic-comp already sets one connector property itself:
  - [`set_max_bpc`](https://github.com/pop-os/cosmic-comp/blob/epoch-1.10.0/src/backend/kms/drm_helpers.rs#L322-L336)
    calls `dev.set_property(conn, get_prop(dev, conn, "max bpc"), …)`, which
    is the legacy SETPROPERTY ioctl.
  - It is called right after `initialize_output`
    ([kms/mod.rs L1132-L1141](https://github.com/pop-os/cosmic-comp/blob/epoch-1.10.0/src/backend/kms/mod.rs#L1132-L1141)).
  - Generic helpers `get_prop` and `get_property_val`
    ([drm_helpers.rs L225-L255](https://github.com/pop-os/cosmic-comp/blob/epoch-1.10.0/src/backend/kms/drm_helpers.rs#L225-L255))
    look up any property by name.
- Smithay's atomic surface puts only `CRTC_ID` on connectors:
  - [surface/atomic.rs L1175-L1182](https://github.com/Smithay/smithay/blob/e3d461a057ba244d213a8498ec372b0799cca103/src/backend/drm/surface/atomic.rs#L1175-L1182)
    and the commit loop at L1346-L1348.
  - Its only extra knob is `VRR_ENABLED` on the CRTC (`use_vrr`, L622).
  - There is no public API for arbitrary connector properties.
  - Smithay also never writes `Broadcast RGB` back, so a value set on the
    side should persist across its commits. *Unverified* at runtime.
- Issues:
  - Searches of cosmic-comp and Smithay issues for broadcast RGB, RGB range,
    limited range and washed out found nothing relevant.
  - [cosmic-epoch#199](https://github.com/pop-os/cosmic-epoch/issues/199)
    "Full RGB range on hdmi" was closed by its reporter, with no linked PR.
    A comment from 2026-08-17 says there is still no setting and CLI tools
    get "permission denied".

## 5. Prior art: KWin and mutter (verified)

- **KWin** has a per-output "RGB range" setting (Automatic / Full / Limited):
  - [drm_connector.cpp L138](https://github.com/KDE/kwin/blob/81fb00607e6d0278f921f4d507ba7be8468412bf/src/backends/drm/drm_connector.cpp#L138)
    binds the `Broadcast RGB` enum property.
  - [`DrmPipeline::prepareAtomicModeset`](https://github.com/KDE/kwin/blob/81fb00607e6d0278f921f4d507ba7be8468412bf/src/backends/drm/drm_pipeline.cpp#L394-L399)
    adds it to every atomic modeset when the property is valid.
  - The setting is persisted per output
    ([outputconfigurationstore.cpp L1261-L1268](https://github.com/KDE/kwin/blob/81fb00607e6d0278f921f4d507ba7be8468412bf/src/outputconfigurationstore.cpp#L1261-L1268)).
  - Because it sits in every modeset, it survives connector re-creation.
- **mutter** has the same feature:
  - `MetaOutputRGBRange` AUTO / FULL / LIMITED
    ([meta-output.h L54-L57](https://github.com/GNOME/mutter/blob/2b9c0787f99dacef16ba987656e28ffcb344b9a2/src/backends/meta-output.h#L54-L57)).
  - Mapped to the DRM property in
    [meta-kms-connector.c L332-L375](https://github.com/GNOME/mutter/blob/2b9c0787f99dacef16ba987656e28ffcb344b9a2/src/backends/native/meta-kms-connector.c#L332-L375).
  - Stored as `<rgbrange>` in `monitors.xml`
    ([meta-monitor-config-store.c L463](https://github.com/GNOME/mutter/blob/2b9c0787f99dacef16ba987656e28ffcb344b9a2/src/backends/meta-monitor-config-store.c#L463)).
  - Exposed as `rgb-range` over D-Bus
    ([meta-monitor-manager.c L2334](https://github.com/GNOME/mutter/blob/2b9c0787f99dacef16ba987656e28ffcb344b9a2/src/backends/meta-monitor-manager.c#L2334)).
  - Whether GNOME Settings shows it in its UI: *unverified*.

## 6. Why userspace tools can't fix it, and why it resets (verified)

- `MODE_SETPROPERTY`, `MODE_OBJ_SETPROPERTY` and `MODE_ATOMIC` are all
  `DRM_MASTER` ioctls
  ([drm_ioctl.c L698, L712, L714](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_ioctl.c#L698-L714)).
  While cosmic-comp is master, `proptest` or `modetest` get EACCES.
- MST connectors are created per topology change in
  [`drm_dp_mst_port_add_connector`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/display/drm_dp_mst_topology.c#L2275-L2296)
  and torn down with the port
  ([`drm_dp_destroy_port`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/display/drm_dp_mst_topology.c#L1829)).
- A new connector gets a fresh state with `Broadcast RGB` = Automatic (0).
  It also gets the lowest free `DP-n` id, from `ida_alloc_min`
  ([drm_connector.c L260-L269](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_connector.c#L260-L269)).
- A KVM switch-away unplugs the MST stream, so any value set by hand is lost
  and the name can change. That a KVM switch re-creates the connector is
  inferred from the topology code: *unverified* on this dock.

## Fix options

### A. Kernel patch: Automatic means full range on non-HDMI DP sinks

This is an **untested sketch** against v7.2. It mirrors the core helper's
`!is_hdmi` rule. The G80SD has no HDMI VSDB, so `is_hdmi` is false
([set only in `drm_parse_hdmi_vsdb_video`](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L6384-L6389)).

```diff
--- a/drivers/gpu/drm/i915/display/intel_dp.c
+++ b/drivers/gpu/drm/i915/display/intel_dp.c
@@ bool intel_dp_limited_color_range(
 	if (intel_conn_state->broadcast_rgb == INTEL_BROADCAST_RGB_AUTO) {
+		/* Local: DP sinks without an HDMI VSDB get full range. */
+		if (!conn_state->connector->display_info.is_hdmi)
+			return false;
 		/*
```

Applied through `boot.kernelPatches = [ { name = …; patch = ./….patch; } ]`.
The [option](https://search.nixos.org/options?query=boot.kernelPatches)
exists, `type = list of attrs`.

- **Effort:** low to write, a full kernel build to test.
- **Robustness:** covers every DP and MST connector, including re-created
  ones. It survives KVM switches and needs no compositor support. Side
  effect: a DP-to-HDMI TV path keeps its CTA default only if its EDID has an
  HDMI VSDB.
- **Maintenance:** high.
  - The current `linux-zen-7.2.11` store path is substitutable from
    `cache.nixos.org` (`nix path-info --store https://cache.nixos.org`, run
    here). A patched kernel is not, so every nixpkgs bump rebuilds zen
    locally ([zen-kernels.nix L21](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/os-specific/linux/kernel/zen-kernels.nix#L21)).
  - The hunk may need rebasing.
  - Upstreaming is a policy change for i915 maintainers: *unverified*
    whether it would be accepted.

### B. cosmic-comp patch: set `Broadcast RGB` = Full

Copy the `set_max_bpc` pattern: after `initialize_output`, call
`dev.set_property(conn, get_prop(dev, conn, "Broadcast RGB")?, 1)`. Use the
enum value for "Full" (1 in i915's list) instead of hard-coding it. Changing
this property is treated as fastset-capable: it sets `mode_changed`
([intel_atomic.c L137-L146](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_atomic.c#L137-L146)),
so expect at most a brief blank.

Package it as a nixpkgs overlay: `cosmic-comp.overrideAttrs { patches = …; }`.

- **Effort:** low to medium. It is a small Rust change with no Smithay
  change, because it bypasses Smithay's atomic state as `max bpc` does.
- **Robustness:** it re-runs whenever cosmic-comp enables an output, which
  should cover re-created MST connectors after KVM switches. *Unverified*
  that this path runs on every MST reconnect.
- **Maintenance:** medium. cosmic-comp is rebuilt locally on each bump (a
  Rust build, much cheaper than a kernel), and the patch may need rebasing
  per epoch release.

### C. EDID override with a non-CTA 4K ~120 Hz timing

The options exist in the pinned nixpkgs:

- `hardware.display.edid.{packages,modelines,linuxhw}`;
- `hardware.display.outputs.<name>.{edid,mode}`
  ([display.nix L133](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/nixos/modules/services/hardware/display.nix#L133)),
  which emits `drm.edid_firmware=<name>:edid/<file>` (L198) and installs the
  files via `hardware.firmware` (L204).

The kernel side:

- The override is applied inside `_drm_do_get_edid`
  ([drm_edid.c L2398-L2405](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L2398-L2405)).
- MST reads the EDID through `drm_edid_read_ddc` → `drm_edid_read_custom`
  ([MST L2292](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/display/drm_dp_mst_topology.c#L2292)),
  so the override does apply to MST connectors.
- The edited EDID must drop VIC 118 (and 97) and add 4K ~120 Hz as a
  non-CTA timing.
- A DTD cannot carry it: the pixel clock is a 16-bit field in 10 kHz units,
  so 655.35 MHz at most
  ([drm_edid.h L191](https://github.com/torvalds/linux/blob/v7.2/include/drm/drm_edid.h#L191),
  [drm_edid.c L3573](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L3573)).
- The timing must go in DisplayID instead: Type VII detailed, or (simpler
  here) one more Type X CVT-RB entry in the existing block. The kernel
  parses both
  ([L6994-L7008](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid.c#L6994-L7008)).
- The `modelines` helper (`edid-generator`) produces only base-block EDIDs:
  *unverified* that it can emit DisplayID, so the EDID is probably
  hand-edited.

- **Effort:** medium to high: binary EDID editing and checksums.
- **Robustness:** poor.
  - `DP-9` is not stable, because the id comes from `ida_alloc_min` and
    depends on probe order.
  - The match is a prefix `strncmp`, so `DP-9:` also matches `DP-90`
    ([drm_edid_load.c L76-L82](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/drm_edid_load.c#L76-L82)).
  - An entry with no connector name becomes a fallback for every connector.
  - The override also hides the real EDID if the monitor changes.
- **Maintenance:** low once working, but fragile when the dock topology
  changes.

### D. Feature request to cosmic-comp

Ask for a per-output "RGB range" (Automatic / Full / Limited), stored in the
output config and applied on every modeset like KWin and mutter (section 5).
Link cosmic-epoch#199 and this analysis.

- **Effort:** low.
- **Robustness:** best long-term, because it is re-applied on every modeset.
- **Maintenance:** none. Timeline unknown.

### E. Workarounds

- Use 3840x2160 @ 59.997 Hz (DTD 1, full range).
  - **Effort:** none.
  - **Robustness:** survives KVM switches, assuming COSMIC restores the
    saved mode.
  - **Cost:** loses 120 Hz.
- Try 3840x2160 @ 239.99 Hz from the DisplayID CVT timing, which is full
  range if offered.
  - *Unverified* that COSMIC lists it, and that DSC over this MST dock link
    has the bandwidth.

## How to verify

1. Open the lagom.nl LCD black-level test full-screen. Squares 1–5 must be
   distinguishable from the background on a correct (full-range) output.
2. Log the modeset, switch modes, then turn logging off:

   ```sh
   echo 0x4 | sudo tee /sys/module/drm/parameters/debug
   # switch mode / replug, then:
   sudo dmesg | grep -iE 'DP-9|limited_color_range|output format|dsc'
   echo 0 | sudo tee /sys/module/drm/parameters/debug
   ```

   The modeset line shows `output format` / `sink format`
   ([intel_crtc_state_dump.c L201](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/i915/display/intel_crtc_state_dump.c#L201)).
   The v7.2 state dump has no line for `limited_color_range`. Infer the range
   from the mode instead: a mode that matches a VIC (step 3) is limited on
   Automatic, and anything else is full.
3. Check whether a mode is CTA:
   `edid-decode /sys/class/drm/card1-DP-*/edid` and compare against the VIC
   list.
