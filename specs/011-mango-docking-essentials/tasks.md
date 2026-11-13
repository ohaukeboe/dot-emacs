# Tasks: Mango Docking and Session Essentials

**Input**: Design documents from `specs/011-mango-docking-essentials/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/options.md](contracts/options.md), [quickstart.md](quickstart.md)

**Tests**: no test suite was requested. Verification is Nix evaluation and
build (Constitution I, III), the assertion probes and manual checks in
[quickstart.md](quickstart.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel: different files, and no dependency on an
  unfinished task. Almost every task edits `modules/mango/default.nix`, so
  few are [P].
- **[Story]**: the user story the task belongs to (US1–US6).

## Rules for every task

- The flake sees only git-tracked files. `git add` every new file before
  `nix build` or `nix flake check`.
- Every package comes from nixpkgs (`pkgs.<name>`); no new flake input or
  nvfetcher entry (FR-017).
- Everything sits inside `mkIf cfg.enable` in `modules/mango/default.nix`
  (FR-019). Home Manager config goes under
  `home-manager.users.${config.user.username}`.
- Every Home Manager user service added is bound to `mango-session.target`:
  use the module option (`systemdTarget`/`systemdTargets`) when it exists,
  else `systemd.user.services.<name> = bindToSession;` (FR-018).
- Scripts are `pkgs.writeShellApplication` with `runtimeInputs`; Mango
  `bind=`/`exec_once=`/`switchbind=` lines reference them with `getExe`
  (Constitution I).
- Assertion messages name `modules/mango/default.nix` and the fix.
- The agent sandbox cannot deploy, log in or dock. Steps marked **(user)**
  are the user's, on `laptop`.

---

## Phase 1: Setup

- [X] T001 Create the beads epic `Mango docking and session essentials
  (specs/011)` linking `specs/011-mango-docking-essentials/`, and file one
  child ticket per phase below, keeping the `T0NN` ids in titles.

---

## Phase 2: Foundational (blocks US1–US3)

- [X] T002 Declare `modules.mango.displays.internal` and
  `modules.mango.displays.setups` in `modules/mango/default.nix` exactly as in
  [contracts/options.md](contracts/options.md) §Options: `internal` is
  `types.nonEmptyStr`, default `"eDP-1"`; each output has `criteria`
  (`types.nonEmptyStr`), `enable` (bool, default `true`), `mode`
  (`types.nullOr (types.strMatching "[0-9]+x[0-9]+(@[0-9.]+(Hz)?)?")`,
  default `null` = preferred), `position.x`/`position.y`
  (`types.ints.unsigned`, default `0`; "no negative coords (XWayland)"),
  `scale` (`types.nullOr` positive float, default `null`); `outputs` is
  `types.nonEmptyListOf`; `setups` defaults to `{ }`.
- [X] T003 Add the assertions from data-model.md to `modules/mango/default.nix`:
  "no two outputs in a setup share `criteria`"; "no setup is called
  `undocked`"; "at least one output per setup is enabled". One assertion per
  setup and rule, message naming the setup.
- [X] T004 Add `mango-lid-sync` (`writeShellApplication`, runtimeInputs
  `coreutils gnugrep` and `config.programs.mango.package` for `mmsg`, plus
  `wlr-randr` and `jq`) in `modules/mango/default.nix` (research R4): read
  `/proc/acpi/button/lid/*/state`; count enabled-or-connected outputs other
  than `cfg.displays.internal` from `wlr-randr --json`; lid `closed` and at
  least one other output → `mmsg dispatch disable_monitor,<internal>`;
  otherwise `mmsg dispatch enable_monitor,<internal>`. Exit 0 when no lid
  file exists.
- [X] T005 Run `nix flake check` and
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`.

**Checkpoint**: options evaluate; `laptop` builds unchanged in behaviour.

---

## Phase 3: User Story 1 - Dock into a known setup (Priority: P1) 🎯 MVP

**Goal**: recorded setups apply automatically on hotplug and session start;
undocking returns to the panel.

**Independent Test**: [quickstart.md](quickstart.md) D3, D4.

- [X] T006 [US1] In `modules/mango/default.nix` enable HM `services.kanshi`
  with `systemdTarget = "mango-session.target"` and `settings` generated from
  `cfg.displays.setups` (research R1, R3; data-model "Generated profiles"):
  one `{ profile = { name; outputs = [{ criteria; status = "enable"|"disable";
  mode?; position = "X,Y"; scale?; }]; exec = [ <mango-lid-sync> ]; }; }`
  per setup, omitting `mode`/`scale` when `null`, plus a fixed `undocked`
  profile: `cfg.displays.internal` enabled at `0,0`, same `exec`.
- [X] T007 [US1] Add `mango-display-setup` (`writeShellApplication`,
  runtimeInputs `wlr-randr jq`) to `modules/mango/default.nix` and
  `home.packages` (research R7): from `wlr-randr --json`, print a
  `modules.mango.displays.setups.<name>.outputs = [ … ];` Nix snippet with
  `criteria` = `"<make> <model> <serial>"` (the output name for the internal
  panel), `enable`, `position`, current mode as `WxH@R`, and `scale`;
  `<name>` from `$1`, default `new-setup`.
- [X] T008 [US1] Add `mango-reload` (`writeShellApplication`) to
  `modules/mango/default.nix` (research R5): `mmsg dispatch reload_config`,
  `kanshictl reload`, then `mango-lid-sync`. In `mangoLines` set
  `auto_reload_config=0` and change `bind=SUPER,r,reload_config` to
  `bind=SUPER,r,spawn,<mango-reload>`.
- [X] T009 [US1] In `machines/machines.nix`, `laptop.modules`, add a comment
  line pointing to `mango-display-setup` for adding setups; add no setup
  (clarification: mechanism only).
- [X] T010 [US1] Build gate from quickstart (fmt, flake check, laptop
  toplevel) and the three assertion probes from quickstart §Build gate.
- [ ] T011 [US1] **(user)** Deploy; run quickstart D3 and D4.

**Checkpoint**: US1 works with any setup the user records.

---

## Phase 4: User Story 2 - Dock into an unknown setup (Priority: P1)

**Goal**: unknown displays light up to the right of the panel; a GUI tool
rearranges them without config edits.

**Independent Test**: [quickstart.md](quickstart.md) D1, D2.

- [X] T012 [US2] Confirm `mangoLines` in `modules/mango/default.nix` contains
  no `monitor_rule` (research R2: Mango's auto placement is the default);
  add a one-line comment saying why.
- [X] T013 [US2] Add `pkgs.wdisplays` to `home.packages` in
  `modules/mango/default.nix` (research R6).
- [ ] T014 [US2] **(user)** Run quickstart D1, D2.

---

## Phase 5: User Story 3 - Every display is part of the desktop (Priority: P2)

**Goal**: bar, wallpaper, lock on every display; lid closed while docked keeps
running on the externals.

**Independent Test**: [quickstart.md](quickstart.md) D5, D6, D7.

- [X] T015 [US3] In `mangoLines` (`modules/mango/default.nix`) add
  `exec_once=<mango-lid-sync>`, `switchbind=fold,spawn,<mango-lid-sync>` and
  `switchbind=unfold,spawn,<mango-lid-sync>` (research R4).
- [X] T016 [US3] Check `config.services.logind.settings.Login` on `laptop`
  does not set `HandleLidSwitchDocked` (default `ignore`); if any module sets
  it, stop and report rather than override (ADR 0001).
- [ ] T017 [US3] **(user)** Run quickstart D5–D7. If D5 shows no suspend after
  undocking with the lid closed, add to `mango-lid-sync`: lid closed and no
  other output → `systemctl suspend`.

---

## Phase 6: User Story 4 - Session gaps closed (Priority: P2)

**Goal**: portal screenshots, screen-share picker, clipboard persistence, OSD,
Bluetooth/audio controls, power menu.

**Independent Test**: [quickstart.md](quickstart.md) G1–G6.

- [X] T018 [US4] In `modules/mango/default.nix` set
  `xdg.portal.config.mango = mkForce { default = [ "gtk" ];
  "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
  "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
  "org.freedesktop.impl.portal.Inhibit" = [ "gtk" ];
  "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ]; }`
  (research R8; the nixpkgs map spells `ScreenShot`).
- [X] T019 [US4] Add the portal-key build check in `modules/mango/default.nix`
  (research R8): a `runCommand` that, for each
  `org.freedesktop.impl.portal.*` key in `config.xdg.portal.config.mango`,
  greps the `Interfaces=` line of
  `<backend>/share/xdg-desktop-portal/portals/<backend>.portal` for the
  backends in `config.xdg.portal.extraPackages` and fails with the key and
  backend named. Reference it from the generated mango config derivation (or
  `system.extraDependencies`) so the `laptop` toplevel build runs it.
- [X] T020 [US4] Set `xdg.portal.wlr.settings.screencast = { chooser_type =
  "simple"; chooser_cmd = "${getExe pkgs.slurp} -f %o -or"; }` in
  `modules/mango/default.nix` (research R9).
- [X] T021 [P] [US4] HM `services.wl-clip-persist = { enable = true;
  clipboardType = "regular"; systemdTargets = [ sessionTarget ]; }` in
  `modules/mango/default.nix` (research R10).
- [X] T022 [US4] swayosd (research R11) in `modules/mango/default.nix`: HM
  `services.swayosd.enable = true` with
  `systemd.user.services.swayosd = bindToSession`;
  `services.udev.packages = [ pkgs.swayosd ]`;
  `users.users.${config.user.username}.extraGroups = [ "video" ]`; replace the
  `wpctl`/`brightnessctl` `bindl=` lines with `swayosd-client
  --output-volume raise|lower|mute-toggle`, `--input-volume mute-toggle`,
  `--brightness raise|lower`; drop the now-unused `wpctl`/`brightnessctl`
  bindings in the `let`.
- [X] T023 [US4] Bluetooth and audio (research R12) in
  `modules/mango/default.nix`: `services.blueman.enable = true`; HM
  `services.blueman-applet = { enable = true; systemdTargets =
  [ sessionTarget ]; }`; add `pkgs.pwvucontrol` to `home.packages`; set
  waybar `wireplumber.on-click = getExe pkgs.pwvucontrol`.
- [X] T024 [US4] Add `mango-power-menu` (`writeShellApplication`, runtimeInputs
  `fuzzel systemd swaylock` and mango for `mmsg`) in
  `modules/mango/default.nix` (research R13): options lock (`swaylock -f`),
  log out (`mmsg dispatch quit`), suspend, reboot, power off (`systemctl`).
  Bind `bind=SUPER+SHIFT,Escape,spawn,<menu>`; add waybar `custom/power`
  (`format = "⏻"`, `on-click` = the menu) at the end of `modules-right`.
- [X] T025 [US4] Build gate (fmt, flake check, laptop toplevel); confirm the
  portal check fails if `Screenshot` is temporarily misspelled, then revert.
- [ ] T026 [US4] **(user)** Deploy, re-login, run quickstart G1–G6.

---

## Phase 7: User Story 5 - Look stays dark without COSMIC (Priority: P3)

**Goal**: GTK3, GTK4 and Qt dark, one cursor, without relying on COSMIC.

**Independent Test**: [quickstart.md](quickstart.md) T.

- [X] T027 [US5] Theming in `modules/mango/default.nix` (research R15): add to
  `mangoLines` `env=GTK_THEME,adw-gtk3-dark`, `env=XCURSOR_THEME,Adwaita`,
  `env=XCURSOR_SIZE,24`, `cursor_theme=Adwaita`, `cursor_size=24`; HM
  `dconf.settings."org/gnome/desktop/interface" = { color-scheme =
  "prefer-dark"; cursor-theme = "Adwaita"; cursor-size = 24; }`; add
  `pkgs.adwaita-icon-theme` to `environment.systemPackages`. Do not enable HM
  `gtk` or `home.pointerCursor.gtk` (they collide with COSMIC's files).
- [X] T028 [US5] Evaluate and build `laptop` with
  `modules.cosmic-de.enable = false` set temporarily in
  `machines/machines.nix`; revert after it builds.
- [ ] T029 [US5] **(user)** Quickstart T in a test boot or VM.

---

## Phase 8: User Story 6 - Annotate a screenshot (Priority: P3)

**Goal**: region screenshot opens in an editor before saving or copying.

**Independent Test**: [quickstart.md](quickstart.md) A.

- [X] T030 [US6] In `modules/mango/default.nix` (research R14): HM
  `programs.satty = { enable = true; settings.general = { output-filename =
  "<Pictures>/Screenshots/%Y-%m-%d_%H-%M-%S.png"; copy-command = "wl-copy"; };
  }` (use the same directory as `mango-screenshot`); add an `annotate)` case to
  the `screenshot` script: `grim -g "$(slurp)" - | satty --filename -`, with
  `satty` in its `runtimeInputs`; bind `bind=CTRL,Print,spawn,<screenshot>
  annotate`.
- [ ] T031 [US6] **(user)** Quickstart A.

---

## Phase 9: Polish & Cross-Cutting

- [X] T032 [P] Correct `specs/010-mango-wm-session/research.md` per research
  R17 (FR-020): `ScreenShot` → `Screenshot`, swaync is
  `pkgs.swaynotificationcenter`, Noctalia/Dux are packaged, `GTK_THEME` came
  from `modules/cosmic-de`, dux-greeter uses `mangowc` but the binary wants
  `mango`. Mark each "Superseded 2026-11-13, see
  docs/mangowm-components-research.md".
- [X] T033 [P] Add **Display setup** and **Undocked profile** to the
  `Desktop / sessions` section of `GLOSSARY.md`.
- [X] T034 If `modules/mango/default.nix` exceeds ~600 lines, move the
  scripts to `modules/mango/scripts.nix` imported by `default.nix` (plan
  Structure Decision).
- [X] T035 Final gate: `nix fmt` (revert unrelated churn), `nix flake check`,
  laptop toplevel build, and confirm `desktop`, `work-laptop`, `dig-laptop`
  toplevel out paths are unchanged versus `main` (SC-008).
- [X] T036 Tick finished tasks `[X]` here and close the matching beads
  tickets in the same change.

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → stories.
- US1 (Phase 3) needs T002–T004. US2 needs nothing beyond Phase 2 (T012 is a
  check). US3 needs T004 and, for D5–D7, kanshi from US1.
- US4, US5, US6 need only Phase 1; they do not depend on the display work.
- Polish after the stories it documents; T032/T033 can run any time.
- All implementation tasks edit `modules/mango/default.nix`, so run them one
  at a time unless working in separate branches.

### Parallel opportunities

- T021 (wl-clip-persist) is a self-contained block.
- T032 (spec 010 research) and T033 (glossary) touch other files.
- Whole stories US4, US5, US6 can be developed in parallel with US1–US3 on
  separate branches; expect merge conflicts only in `mangoLines`.

## Implementation Strategy

1. **MVP**: Phases 1–3 plus T012–T013 (US1 + US2): the laptop docks into
   known and unknown setups. Deploy and run D1–D4.
2. Add US3 (lid while docked), then deploy and run D5–D7.
3. Add US4 (gaps), deploy, run G1–G6.
4. Add US5 and US6, then Polish.
