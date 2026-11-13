# Implementation Plan: Mango Docking and Session Essentials

**Branch**: `011-mango-docking-essentials` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-mango-docking-essentials/spec.md`

## Summary

Extend `modules/mango` so the laptop docks well and the session gaps from
`docs/mangowm-components-research.md` are closed. Known display setups are
typed data (`modules.mango.displays.setups`) rendered to kanshi profiles,
plus an always-present `undocked` profile. Unknown displays fall to Mango's
built-in auto placement (to the right). A `mango-lid-sync` script, fired by
Mango's lid `switchbind`, kanshi `exec` and session start, turns the panel
off when the lid is closed while docked; logind already ignores the lid when
docked. Also: the misspelled portal Screenshot key is fixed and guarded by a
build check, an explicit screen-share picker, wl-clip-persist, swayosd,
blueman and pwvucontrol, a power menu, satty annotation, and Mango-scoped
theming so COSMIC can later be turned off. Details: [research.md](research.md).

## Technical Context

**Language/Version**: Nix (flakes, nixpkgs pinned in `flake.lock`), NixOS
modules, Home Manager as a NixOS module; shell via `writeShellApplication`.

**Primary Dependencies** (nixpkgs only): kanshi 1.9.0, wlr-randr 0.5.0, jq,
wdisplays 1.3.0, swayosd 0.3.2, wl-clip-persist 0.5.0, blueman 2.4.6,
pwvucontrol 0.5.3, satty 0.22.0, adwaita-icon-theme, slurp; existing mango
0.18.4, waybar, fuzzel, swaylock, xdg-desktop-portal-wlr/-gtk.

**Storage**: N/A. Setups live in `machines/machines.nix`; kanshi config is
generated.

**Testing**: `nix flake check`; `laptop` toplevel build, which runs `mango -p`
on the generated config and the new portal-key check; assertion probes; the
manual run-through in [quickstart.md](quickstart.md).

**Target Platform**: NixOS x86_64, machine `laptop` (AMD, panel `eDP-1`).

**Project Type**: NixOS configuration module (extension of `modules/mango`).

**Performance Goals**: recorded arrangement within 5 s of plugging in
(SC-001); unknown display usable within 5 s (SC-002).

**Constraints**: nixpkgs only (FR-017); services only in the Mango session
(FR-018); no change to COSMIC's look (FR-016) or the other three machines
(SC-008); ADR 0001 lid/suspend behaviour kept when undocked.

**Scale/Scope**: `modules/mango/default.nix` grows by ~200 lines (options,
five small scripts, service blocks); one data entry point in
`machines/machines.nix` (empty for now); edits to spec 010 `research.md`
and `GLOSSARY.md`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Evaluation-time checks**: Pass. Setups are typed submodules
  (`nonEmptyStr`, `strMatching` for modes, `ints.unsigned` positions,
  positive-float scale); duplicate criteria, the reserved `undocked` name
  and all-disabled setups are assertions. Scripts are
  `writeShellApplication` and reference tools via `getExe`. The portal-key
  check makes the Screenshot typo class a build error.
- **II. Determinism**: Pass. All config generated; setups are data in the
  machine registry; the print command produces data to commit, not local
  state.
- **III. Fast gate**: Pass. No new `checks.*`. The portal-key check is a tiny
  `runCommand` in the laptop toplevel build, like `mango -p`. The R8 fix is a
  bug evaluation could not catch, so it ships with that guard.
- **IV. Single source of truth**: Pass. New terms (Display setup, Undocked
  profile) go into `GLOSSARY.md`. Spec 010 `research.md` is corrected, not
  duplicated. ADR 0001 is respected (lid suspend when undocked unchanged);
  no ADR needed: every choice here is cheap to reverse.
- **V. Toggleable modules**: Pass. All additions inside `mkIf cfg.enable`;
  setups default to `{ }`; services bound to `mango-session.target`. NixOS-
  level additions (`services.blueman`, swayosd udev rules, `video` group,
  `xdg.portal.wlr.settings`) are only present when the module is on.

Post-design re-check: still Pass. Two notes:

- Adding the user to group `video` widens backlight write access to the user
  in every session. Accepted: it is the swayosd-documented setup and only
  affects `/sys/class/backlight`.
- `services.blueman` and the portal config are system-wide while the module is
  on, so they also exist under COSMIC. Both are passive (D-Bus activated /
  only read by xdpw, which only Mango uses), so FR-016/FR-018 hold.

## Project Structure

### Documentation (this feature)

```text
specs/011-mango-docking-essentials/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/options.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
modules/mango/default.nix              # options, scripts, services, bindings
machines/machines.nix                  # laptop: displays.setups (empty now)
specs/010-mango-wm-session/research.md # FR-020 corrections
GLOSSARY.md                            # Display setup, Undocked profile
```

**Structure Decision**: Everything stays in the existing `modules/mango`
module; no new module, since none of it makes sense without Mango. If
`default.nix` passes ~600 lines, split the scripts into
`modules/mango/scripts.nix` imported by `default.nix`.

## Risks

| Risk                                          | Mitigation                          |
|-----------------------------------------------|-------------------------------------|
| logind may not re-check the lid on undock     | quickstart D5; script fallback (R4) |
| Mango reload re-enables kanshi-disabled panel | no auto-reload; `mango-reload` (R5) |
| kanshi and Mango race on hotplug              | kanshi applies last; quickstart D3  |
| swayosd brightness without `video` group      | udev rules + group; re-login        |
| libadwaita dark mode untested under gtk portal| quickstart T                        |
| Mango key renames in a nixpkgs bump           | `mango -p` fails the build          |

## Complexity Tracking

No constitution violations.
