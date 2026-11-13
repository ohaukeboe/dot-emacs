# Tasks: Mango Window Manager Session

**Input**: Design documents from `specs/010-mango-wm-session/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/options.md](contracts/options.md), [quickstart.md](quickstart.md)

**Tests**: no test suite was requested. Verification is Nix evaluation and
build (Constitution I, III), the assertion probes in `quickstart.md` §3, and
the manual checks in `quickstart.md` §4.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel: different files, and no dependency on an
  unfinished task.
- **[Story]**: the user story the task belongs to (US1–US3).

## Rules for every task

- The flake sees only git-tracked files. `git add` every new file before
  `nix build` or `nix flake check`.
- Every package comes from nixpkgs (`pkgs.<name>`). No new flake input or
  nvfetcher entry (FR-009).
- Use `config.user.username`, never the literal user name. Home Manager
  config goes under `home-manager.users.${config.user.username}`, as in
  `modules/cosmic-de/default.nix:662`.
- Everything in `modules/mango/` sits inside `mkIf cfg.enable` (FR-010).
- Executables in mango `bind=` / `exec_once=` lines are referenced with
  `lib.getExe` / `lib.getExe'`, never bare names (Constitution I).
- Assertion messages name the file and the fix.
- Every Home Manager user service the module adds is bound to
  `mango-session.target`, never `graphical-session.target`, so it stays down
  under COSMIC (research R4, FR-011).
- The agent sandbox cannot deploy or log in. Steps marked **(user)** are the
  user's, on `laptop`.

---

## Phase 1: Setup

- [X] T001 Create the beads epic `Mango window manager session (specs/010)`
  linking `specs/010-mango-wm-session/`, with one child ticket per phase
  below, titles keeping the `T0NN` ids.
- [X] T002 Create `modules/mango/default.nix` (empty module with `cfg =
  config.modules.mango`) and `modules/mango/module.nix` (`imports = [
  ./default.nix ];`, same as `modules/cosmic-de/module.nix`); add
  `./mango/module.nix` to `modules/default.nix`; `git add modules/mango`.

---

## Phase 2: Foundational (blocks all stories)

- [X] T003 Declare the options in `modules/mango/default.nix` exactly as in
  `contracts/options.md`: `enable = mkEnableOption "Mango window manager
  session"`; `greeter.enable` (`types.bool`, default `true`); `terminal =
  mkPackageOption pkgs "foot" { }`; `lockAfter` (`types.ints.positive`,
  default `300`); `screenOffAfter` (`types.ints.positive`, default `600`).
- [X] T004 [P] In `modules/cosmic-de/default.nix` add
  `options.modules.cosmic-de.greeter.enable` (`types.bool`, default `true`,
  description: turn off to let another module own the login screen) and
  change line 603 to
  `services.displayManager.cosmic-greeter.enable = cfg.greeter.enable;`.
- [X] T005 In `modules/mango/default.nix` add the assertions from
  `contracts/options.md`: (a) `!(cfg.greeter.enable &&
  config.services.displayManager.cosmic-greeter.enable)`, message naming
  `modules/mango/default.nix` and the fix "set
  `modules.cosmic-de.greeter.enable = false`"; (b) `cfg.screenOffAfter >
  cfg.lockAfter`, message naming `modules.mango.screenOffAfter`.
- [X] T006 Run `nix flake check` and
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`;
  both pass with the module still disabled everywhere.

**Checkpoint**: options exist; nothing enabled; all machines evaluate.

---

## Phase 3: User Story 1 - Log in to a Mango session (Priority: P1) 🎯 MVP

**Goal**: on `laptop`, the Mango login screen offers Mango and COSMIC, and
Mango starts with a terminal and a launcher.

**Independent test**: `quickstart.md` §1, then the first two and the
Super+Shift+e rows of §4.

- [X] T007 [US1] In `modules/mango/default.nix` (inside `mkIf cfg.enable`):
  `programs.mango.enable = true;` and
  `systemd.packages = [ config.programs.mango.package ];` so
  `mango-session.target` exists (research R1).
- [X] T008 [US1] In `modules/mango/default.nix` add the login screen, inside
  `mkIf cfg.greeter.enable`:
  `services.displayManager.regreet.enable = true;` with
  `theme = { package = pkgs.adw-gtk3; name = "adw-gtk3-dark"; }` and
  `settings.GTK.application_prefer_dark_theme = true`;
  `security.pam.services.greetd.enableGnomeKeyring = true;` (research R2).
  Check option names against the pinned module
  `nixos/modules/services/display-managers/regreet.nix`.
- [X] T009 [US1] (Done inline in `modules/mango/default.nix` as `mangoLines` +
  `mangoConfig`; no separate file was needed.) Create the config renderer in
  `modules/mango/config.nix`: a
  function `{ pkgs, lib, cfg, ... }: settings -> derivation` that renders a
  list of `{ key; value; }` pairs (repeat keys allowed, for `bind`,
  `exec_once`, `env`) to `key=value` lines with `pkgs.writeText`, then runs
  `HOME=$TMPDIR ${lib.getExe pkgs.mango} -c $file -p` in a `runCommand` and
  copies the file to `$out` on success. If `-p` cannot run headless in the
  build sandbox, drop the check and write `shortcut: no build-time mango
  config check, mango -p needs a display; revisit if upstream adds a headless
  check` above the renderer.
- [X] T010 [US1] In `modules/mango/default.nix` set
  `home-manager.users.${config.user.username}.xdg.configFile."mango/config.conf".source`
  to the T009 derivation, with the base bindings from
  `contracts/options.md`: Super+Return `lib.getExe cfg.terminal`, Super+d
  fuzzel, Super+q close, Super+arrows focus, Super+Shift+arrows move,
  Super+1..9 view tag, Super+Shift+1..9 tag window, Super+f fullscreen,
  Super+Shift+f floating, Super+Shift+e quit. Look up mango action names
  (`killclient`, `focusdir`, `move_client`, `view`, `tag`,
  `togglefullscreen`, `togglefloating`, `quit`) in the package's
  `assets/config.conf`.
- [X] T011 [US1] In `modules/mango/default.nix` add HM
  `programs.fuzzel.enable = true` with a dark colour set (background
  `171717ff`) and the terminal set to `lib.getExe cfg.terminal`;
  `home.packages = [ cfg.terminal ]`.
- [X] T012 [US1] In `machines/machines.nix`, `laptop.modules`, add
  `{ modules.cosmic-de.greeter.enable = false; }` and
  `{ modules.mango.enable = true; }` after the cosmic-de line.
- [X] T013 [US1] Run `quickstart.md` §1 (fmt, flake check, laptop toplevel
  build) and §3 first bullet (re-enable the COSMIC greeter, expect the T005
  message, revert).
- [X] T014 [US1] **(user)** Deploy with
  `sudo nixos-rebuild switch --flake .#laptop`, log in to Mango, open terminal
  and launcher, tile two windows, switch tag, Super+Shift+e back to the login
  screen.

**Checkpoint**: MVP. Mango and COSMIC both reachable from ReGreet.

---

## Phase 4: User Story 2 - Daily-use essentials (Priority: P2)

**Goal**: bar, notifications, lock, idle, polkit, clipboard, screenshots,
media keys, input settings, portals, keyring, password shortcuts.

**Independent test**: `quickstart.md` §4 rows tagged US2, FR-006, FR-007,
FR-008.

- [X] T015 [US2] In `modules/mango/default.nix` (system side):
  `services.gnome.gnome-keyring.enable = true;`
  `services.gnome.gcr-ssh-agent.enable = false;` (same values and comment as
  `modules/cosmic-de/default.nix:611-617`, FR-007);
  `services.power-profiles-daemon.enable = true;`
  `environment.systemPackages = [ pkgs.adw-gtk3 ];` (research R6).
- [X] T016 [US2] Add input settings to the mango config in
  `modules/mango/default.nix`, values from research R3:
  `xkb_rules_layout=eu`,
  `xkb_rules_options=terminate:ctrl_alt_bksp,caps:ctrl_modifier`,
  `repeat_delay=600`, `repeat_rate=25`, `tap_to_click=1`, `tap_and_drag=1`,
  `drag_lock=0`, `trackpad_natural_scrolling=1`; and
  `env=QT_QPA_PLATFORMTHEME,gtk3` (research R6).
- [X] T017 [P] [US2] HM `programs.waybar` in `modules/mango/default.nix`:
  `systemd.enable = true` bound to `mango-session.target`; one thin top bar
  with modules `ext/workspaces` or the mango tag module waybar supports
  (check waybar 0.15 docs for `dwl/tags`), `clock` (`{:%H:%M}`, weeks start
  Monday), `battery`, `network`, `pulseaudio` (or `wireplumber`),
  `power-profiles-daemon`, `tray`; dark style background `#171717`.
- [X] T018 [P] [US2] HM `services.mako` in `modules/mango/default.nix`,
  dark colours, default timeout 5000 ms, bound to `mango-session.target`.
- [X] T019 [P] [US2] HM `programs.swaylock` (colour `171717`) and
  `services.swayidle` in `modules/mango/default.nix`: lock at
  `cfg.lockAfter`, `wlopm --off '*'` (or mango's DPMS action) at
  `cfg.screenOffAfter` with resume back on, `before-sleep` lock; systemd
  target `mango-session.target`. Add Super+Escape bind to
  `lib.getExe pkgs.swaylock` with `-f`.
- [X] T020 [P] [US2] HM `services.hyprpolkitagent.enable = true` in
  `modules/mango/default.nix`, unit bound to `mango-session.target` (override
  `systemd.user.services.hyprpolkitagent` `Install.WantedBy` / `Unit.PartOf`
  if HM hardcodes `graphical-session.target`).
- [X] T021 [P] [US2] HM `services.cliphist.enable = true` bound to
  `mango-session.target`; bind Super+v to a `writeShellApplication`
  `mango-clip-pick` (`cliphist list | fuzzel --dmenu | cliphist decode |
  wl-copy`, runtimeInputs cliphist fuzzel wl-clipboard) in
  `modules/mango/default.nix`.
- [X] T022 [P] [US2] Screenshots in `modules/mango/default.nix`:
  `writeShellApplication` `mango-screenshot` taking `full|region`, saving to
  `$(xdg-user-dir PICTURES)/Screenshots/%Y-%m-%d_%H-%M-%S.png` and copying to
  the clipboard (runtimeInputs grim slurp wl-clipboard xdg-user-dirs
  coreutils); bind Print and Shift+Print.
- [X] T023 [P] [US2] Media and brightness binds in the mango config:
  XF86AudioRaiseVolume/LowerVolume/Mute/MicMute to `wpctl` (from
  `pkgs.wireplumber`), XF86MonBrightnessUp/Down to
  `lib.getExe pkgs.brightnessctl` `set 5%+` / `5%-`, XF86AudioPlay/Next/Prev
  to `lib.getExe pkgs.playerctl`. Use mango's repeat-capable bind form if it
  has one.
- [X] T024 [P] [US2] Wallpaper and tray in `modules/mango/default.nix`:
  `exec_once` `swaybg -c '#171717'` (`lib.getExe pkgs.swaybg`); HM
  `services.network-manager-applet.enable = true` bound to
  `mango-session.target`.
- [X] T025 [US2] Password binds in the mango config: Super+Space to
  `lib.getExe pkgs.proton-pass`, Super+Shift+Space to `1password
  --quick-access` via the 1Password package the repo already installs (find it
  with `rg -n 1password workstation`). Record the cosmic-pass gap from
  research R5 as a code comment.
- [X] T026 [US2] Run `quickstart.md` §1 again; fix any HM option-name errors
  against the pinned Home Manager.
- [X] T027 [US2] **(user)** Deploy and work through `quickstart.md` §4 rows
  for US2, FR-006, FR-007, FR-008.

**Checkpoint**: Mango usable for a full working day.

---

## Phase 5: User Story 3 - COSMIC fallback and clean toggle (Priority: P3)

**Goal**: COSMIC unchanged under the Mango login screen; toggle off leaves no
trace; Mango alone builds.

**Independent test**: `quickstart.md` §2, §3, and the last two rows of §4.

- [X] T028 [US3] Run `quickstart.md` §2: `drvPath` of `desktop`,
  `work-laptop`, `dig-laptop` identical before and after the change (SC-005).
- [X] T029 [US3] Run `quickstart.md` §3 bullets 2 and 3 on throwaway edits to
  `machines/machines.nix`: Mango off ⇒ `nix path-info -r` of the laptop
  toplevel contains no `mango`, `regreet`, `waybar` (SC-004, FR-010); COSMIC
  off with Mango on ⇒ build succeeds (SC-007, FR-014). Revert both edits.
- [X] T030 [US3] **(user)** Pick COSMIC on the Mango login screen; confirm
  panel, shortcuts, theme as before (FR-011). Every unit below must report
  `inactive`, and `pgrep -x mako` must print nothing (mako is D-Bus
  activated, not a unit):
  `systemctl --user is-active mango-session.target blueman-applet cliphist
  cliphist-images hyprpolkitagent kanshi kdeconnect kdeconnect-indicator
  network-manager-applet quickshell swayidle swayosd waybar wl-clip-persist`.
  The unit list is every Home Manager user service bound to
  `mango-session.target`.

**Checkpoint**: all three stories done.

---

## Phase 6: Polish

- [X] T031 [P] Add **Session** and **Login screen** terms to `GLOSSARY.md`
  if absent (Session: what the user picks at login, Mango or COSMIC; Login
  screen: the greeter, owned by one module).
- [X] T032 [P] Mention the Mango module and `cosmic-de.greeter.enable` in
  `AGENTS.md` and `CLAUDE.md` only if they list modules (documentation
  parity).
- [X] T033 `nix fmt`, revert unrelated churn, `nix flake check`, laptop
  toplevel build; tick the matching `tasks.md` lines and close the beads
  tickets.

---

## Dependencies

```text
T001, T002 ─► T003 ─► T005 ─► T006 ─► US1 (T007‥T014) ─► US2 (T015‥T027)
              T004 ──────────┘                       └─► US3 (T028‥T030)
                                                         Polish (T031‥T033)
```

- US2 and US3 both need US1 (the session must exist). US2 and US3 do not
  depend on each other; US3's automated checks (T028, T029) can run right
  after T013.
- Within US2, T017–T024 touch different blocks of
  `modules/mango/default.nix`; mark them [P] only if each lands in its own
  file. Simplest is to run them one after another and treat [P] as "no
  ordering constraint".

## Parallel examples

- Phase 2: T004 (`modules/cosmic-de/default.nix`) alongside T003/T005
  (`modules/mango/default.nix`).
- US2: T017 waybar, T018 mako, T019 lock/idle, T020 polkit, T021 clipboard
  have no ordering between them.
- Polish: T031 and T032.

## Implementation strategy

1. MVP: Phases 1–3. Deploy; log in to Mango; COSMIC still one click away.
2. Phase 4 adds the daily essentials; deploy and use for a day.
3. Phase 5 proves the fallback and toggle; Phase 6 tidies up.
4. Later (outside this spec): drop `modules.cosmic-de` from `laptop`.
