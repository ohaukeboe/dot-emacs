# MangoWM session: component choices

Research for moving the laptop from COSMIC to Mango (`modules/mango`, spec
`specs/010-mango-wm-session`). It extends
[`research.md`](../specs/010-mango-wm-session/research.md), which records why
each current pick was made. This file does not repeat that; it weighs the
alternatives, and flags where `research.md` is wrong or stale.

**Metrics gathered 2026-11-13.** Stars, open issues and archive state come from
the GitHub search API; release dates from each repo's releases API (or the
Codeberg API for Codeberg projects). "Pinned" versions come from evaluating the
nixpkgs this flake locks (`nixos-unstable` tarball, lastModified 2026-11-03)
and the options of `nixosConfigurations.laptop`, including its Home Manager
(rev `b787c48e`, 2026-11-04). "HM" means a Home Manager module exists there;
"NixOS" means a NixOS module exists. A `-` means the item does not exist or was
not checked. Stars are a popularity signal only; issue counts include PRs.

Constraint carried over from the spec: components come from **nixpkgs only**
(`specs/010-mango-wm-session/spec.md`, line 218). Flake-only projects are noted
but count as out of scope unless that rule changes.

## 1. Summary: decisions and recommended defaults

| Component      | Current module             | Recommended default                     |
|----------------|----------------------------|-----------------------------------------|
| Compositor     | mango 0.18.4 (nixpkgs)     | Keep; budget for config churn           |
| Bar            | waybar, `ext/workspaces`   | Keep; `mango/*` modules once 0.16 lands |
| Desktop shell  | none (pieces)              | Keep pieces; Noctalia is the fallback   |
| Launcher       | fuzzel                     | Keep                                    |
| Notifications  | mako                       | Keep; swaync if you want a centre/DND   |
| Lock / idle    | swaylock / swayidle        | Keep                                    |
| Polkit agent   | hyprpolkitagent            | Keep, or soteria (one-line swap)        |
| Clipboard      | cliphist                   | Keep; add wl-clip-persist               |
| Screenshots    | grim + slurp script        | Keep; add satty for annotation          |
| Recording      | none                       | wf-recorder, or OBS through the portal  |
| Portals        | nixpkgs mango defaults     | Fix the `Screenshot` key; set chooser   |
| XWayland       | mango built-in             | Keep                                    |
| Outputs        | none                       | mango `monitor_rule`; kanshi if docking |
| Wallpaper      | swaybg, flat colour        | Keep                                    |
| OSD            | none                       | swayosd                                 |
| Net, BT, audio | nm-applet                  | Add blueman applet and pwvucontrol      |
| Night light    | none                       | wlsunset (if wanted)                    |
| Keyring        | gnome-keyring              | Keep                                    |
| Greeter        | greetd + ReGreet           | Keep; tuigreet as fallback              |
| Theming        | adw-gtk3 (via COSMIC env)  | Own GTK/Qt/cursor/dconf settings        |
| Session        | `mango-session.target`     | Keep; no uwsm                           |
| Power menu     | none (`Super+Shift+e`)     | fuzzel dmenu script, or wleave          |
| File manager   | COSMIC Files (from COSMIC) | Keep cosmic-files standalone            |

Decisions the user has to make (each section below has the evidence):

1. **Mango at all.** One maintainer writes almost all of it and minor
   releases break config about monthly (§3). Accept, or pick niri/sway.
2. **Pieces or a shell.** Keep the assembled stack, or replace bar, launcher,
   notifications, lock, OSD and applets with Noctalia or Dux Shell (§5).
3. **Notification centre.** mako (popups only) or swaync (history panel and
   do-not-disturb) (§7).
4. **Polkit agent.** hyprpolkitagent (Hyprland toolkit) or soteria (GTK4) (§9).
5. **Theming after COSMIC.** Today GTK3 dark mode comes from the COSMIC
   module's `GTK_THEME`. Something must own GTK/Qt/cursor/color-scheme once
   COSMIC is gone (§21).
6. **Multi-monitor.** Static `monitor_rule` lines, or kanshi profiles for
   docking (§14).
7. **Extras:** OSD, night light, screen recording, power menu, Bluetooth
   applet. None is required; each is a small add.

## 2. Corrections to `research.md`

- **R1, portals: the nixpkgs module misspells the Screenshot key.**
  [`nixos/modules/programs/wayland/mango.nix`][nix-mango] sets
  `"org.freedesktop.impl.portal.ScreenShot" = [ "wlr" ]`. The interface is
  `org.freedesktop.impl.portal.Screenshot`, as
  `xdg-desktop-portal-wlr`'s `wlr.portal` lists it (checked in the pinned
  package's `share/xdg-desktop-portal/portals/wlr.portal`). Upstream's own docs
  spell it correctly ([xdg-portals.md][m-portals]). So the Screenshot portal
  goes to the default `gtk`, and `xdg-desktop-portal-gtk` 1.15.3 does not
  implement Screenshot (its `.portal` interface list has no Screenshot).
  Portal-based screenshots (Flatpak apps, browsers) will probably fail. Fix in
  `modules/mango`:
  `xdg.portal.config.mango."org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];`
  and report it upstream. `research.md` repeats the misspelling as fact.
- **R2, dux-greeter: "likely broken" is confirmed.** The nixpkgs
  [`dux-greeter.nix`][nix-duxg] module's `compositor.name` enum offers
  `"mangowc"` (not `"mango"`) and passes it as `--command mangowc`. The
  pinned `dms-greeter` 2.0.0 binary lists its supported compositors as
  `niri, hyprland, sway, scroll, miracle, mango, labwc, aqueous` and contains
  no `mangowc` string at all (checked with `strings`). The module cannot drive
  Mango today.
- **R4, "swaync (not in this nixpkgs under that attribute)": wrong.** It is
  `pkgs.swaynotificationcenter` 0.12.6 (pinned), with HM `services.swaync`.
- **R4, "DankMaterialShell/Noctalia, not in the nixpkgs-only spirit": stale.**
  DankMaterialShell is now **Dux Shell** ([duxlabs-dev/dux-shell][dux]).
  nixpkgs has `dux-shell` 2.0.0 with NixOS `programs.dux-shell` (renamed from
  `programs.dms-shell`, [module][nix-dux]). Noctalia is `pkgs.noctalia` 5.4.1
  with NixOS `programs.noctalia` and HM `programs.noctalia`. Both are
  nixpkgs-only compatible now. Size is still a fair objection.
- **R4, hyprpolkitagent:** it is now built on hyprtoolkit
  ([repo description][hpa]), not "Hyprland libs" in general; the conclusion
  (it works outside Hyprland) is unchanged.
- **R6, `GTK_THEME`:** "keep `GTK_THEME` (it only needs the theme package)"
  misses that the variable itself comes from `modules/cosmic-de`
  (`environment.sessionVariables.GTK_THEME`, line 324). Once COSMIC is
  disabled, GTK3 apps lose the dark theme. See §21.
- **Upstream install docs are stale for NixOS:** [installation.md][m-install]
  uses `pkgs.greetd.tuigreet`, which no longer exists in nixpkgs (the pinned
  attribute is top-level `tuigreet` 0.11.1).

## 3. Mango itself

| Compositor | Stars | Latest release       | Pinned nixpkgs | Notes                  |
|------------|-------|----------------------|----------------|------------------------|
| mango      | 4.1k  | 0.18.5, 2026-11-04   | 0.18.4         | NixOS `programs.mango` |
| niri       | 29.0k | v26.04, 2026-04-25   | 26.04          | Smithay, Rust          |
| Hyprland   | 40.6k | v0.57.2, 2026-11-09  | 0.57.1         | own stack (aquamarine) |
| sway       | 17.5k | 1.12, 2026-05-25     | 1.12           | wlroots reference      |
| river      | 4.3k  | (GitHub is a mirror) | 0.5.0          | layouts are external   |

Sources: [mango][mango], [releases][mango-rel], [niri][niri],
[Hyprland][hypr], [sway][sway], [river][river] (GitHub repo is marked
"[mirror]").

**Health.** The repo moved from `DreamMaoMao/mangowc` to
[`mangowm/mango`][mango]. Last push 2026-11-12, 198 open issues + PRs,
releases about weekly (0.16.1 on 2026-08-16 through 0.18.5 on 2026-11-04,
14 releases; [releases][mango-rel]). The contributor list has about 100
entries, but DreamMaoMao has 2077 commits against 23 for the next person, and
wrote 87 of the last 100 commits since 2026-08-13 ([contributors API][m-contrib],
[commits API][m-commits]). The project is effectively one maintainer.

**Stability.** Every recent minor release has a "Breaking Changes" section:
0.15.0 dropped the dwl IPC protocol, 0.16.0 removed `ov_no_resize`, 0.17.0
changed special tags, 0.18.0 renamed config keys and added TOML
([0.15.0][m-015], [0.16.0][m-016], [0.17.0][m-017], [0.18.0][m-018]). The
README says "Breaking changes will be minimal" ([README][mango]); the release
notes show otherwise. The build-time `mango -c … -p` check in
`modules/mango` is what keeps this survivable: a renamed key fails the build,
not the login.

**Base.** dwl fork on wlroots 0.20.2 and scenefx 0.5 (pinned build inputs;
[installation.md][m-install]). It implements the protocols the session tools
need: `ext-session-lock`, `ext-idle-notify`, `wlr-gamma-control`,
`wlr-output-management`, `wlr-screencopy`, `ext-image-copy-capture`,
`ext/wlr-data-control`, foreign-toplevel, and `ext-workspace`
(includes in [`src/main.c`][m-main], [`src/ext-protocol/`][m-ext]).

**Config.** `~/.config/mango/config.conf` (`key=value`, `source=` includes)
or, since 0.18.0, `config.toml` ([basics.md][m-basics]). Hot reload on by
default (`auto_reload_config`, [miscellaneous.md][m-misc]).

**IPC.** `mmsg`, JSON over a Unix socket named by `MANGO_INSTANCE_SIGNATURE`:
`get`, `watch` (tags, clients, monitors, keymode, layout) and `dispatch`
([ipc.md][m-ipc]). The old `dwl-ipc` Wayland protocol is gone since 0.15.0.

**Nix.** nixpkgs `programs.mango` installs the package, registers the
session and sets portal config ([module][nix-mango]). Upstream's flake adds a
NixOS module and an HM module `wayland.windowManager.mango` with `settings`,
`extraConfig` and `systemd.*` options ([nix-options.md][m-nixopt]); not usable
under the nixpkgs-only rule, and the repo's own attrset-to-`key=value`
renderer plus `-p` check covers the same ground.

**Recommendation.** Mango is a reasonable bet for a single-user laptop: it is
packaged on many distros, actively released, and supported by the large
shells. The real risk is the bus factor and monthly config breakage, not
missing features. niri is the lower-risk alternative if tags/dwm-style layouts
are not essential (larger community, slower and calmer releases); sway if
stability matters most. **Decision:** accept the bus-factor risk, or not.

## 4. Bar

| Bar        | Stars | Latest release     | Pinned      | HM  | Mango tags          |
|------------|-------|--------------------|-------------|-----|---------------------|
| waybar     | 12.2k | 0.16.0, 2026-11-05 | 0.15.0      | yes | ext, then `mango/*` |
| ironbar    | 1.5k  | 0.19.1, 2026-09-20 | 0.19.1      | no  | no                  |
| eww        | 12.8k | 0.6.0, 2024-04-21  | git 2026-07 | yes | DIY (`mmsg`)        |
| quickshell | 3.2k  | 0.3.2, 2026-10-08  | 0.3.2       | yes | DIY QML             |
| AGS        | 3.1k  | 3.1.2, 2026-04-08  | removed     | no  | DIY                 |

Sources: [waybar][waybar], [waybar 0.16.0][wb-016], [ironbar][ironbar],
[ironbar workspaces wiki][ironbar-ws], [eww][eww], [quickshell][qs],
[AGS][ags]. AGS in nixpkgs throws "'ags' and 'astal' ecosystem is no longer
packaged in nixpkgs, use upstream flake instead" (pinned eval).

- waybar 0.16.0 added native `mango/workspaces`, `mango/window`,
  `mango/layout`, `mango/keymode` and `mango/language`, written by the Mango
  maintainer ([PR #5078][wb-5078], [0.16.0 notes][wb-016]). Pinned nixpkgs has
  0.15.0, so the current `ext/workspaces` module is the right choice today; it
  works because Mango implements `ext-workspace` ([source][m-ext]).
- ironbar's workspace module supports only Sway, Hyprland and Niri
  ([wiki][ironbar-ws]); `ext-workspace` support is an open request
  ([#820][ironbar-820]). Not usable for tags.
- eww has had no release since 2024-04 and nixpkgs builds a git snapshot.

**Recommendation:** keep waybar. When nixpkgs reaches 0.16, switch to
`mango/workspaces` (tag-aware) and consider `mango/layout`. **Decision:**
none now.

**Update (2026-11-13):** nixpkgs now pins waybar 0.16.0, and the rail from
`specs/012-mango-rail-bar` uses `mango/workspaces`. Quickshell draws only
the rail's two popups (quick controls, calendar); §5 still stands, no
desktop shell is adopted.

## 5. Full desktop shells

| Shell           | Stars | Latest release    | Pinned | Module     | Mango  |
|-----------------|-------|-------------------|--------|------------|--------|
| Noctalia        | 12.0k | 5.5.0, 2026-11-12 | 5.4.1  | NixOS + HM | listed |
| Dux Shell (DMS) | 9.1k  | 2.1.2, 2026-11-08 | 2.0.0  | NixOS      | listed |
| caelestia       | 13.4k | 2.5.0, 2026-09-18 | 2.5.0  | -          | no     |
| end-4 dots      | 16.6k | -                 | -      | -          | no     |

Sources: [Noctalia][noct], [Noctalia releases][noct-rel], [Dux][dux],
[Dux releases][dux-rel], [caelestia][cael] (README: "Window manager:
Hyprland"), [end-4][end4] (Hyprland dotfiles).

- **Noctalia** is no longer a Quickshell config: it is a native C++
  Wayland/OpenGL ES shell "with no Qt or GTK dependency", covering bar, dock,
  launcher, control centre, notifications, wallpaper, OSD, lock screen,
  session menu and clipboard history. It names Mango among its compositor
  integrations ([README][noct]). Releases every 1-2 weeks.
- **Dux Shell** (formerly DankMaterialShell) is Quickshell + a Go daemon and
  "replaces waybar, swaylock, swayidle, mako, fuzzel, polkit, and everything
  else"; it lists MangoWC as fully supported ([README][dux]). The nixpkgs
  module's default `systemd.target` is `graphical-session.target`
  ([module][nix-dux]), and its companion greeter does not work with Mango in
  nixpkgs (§2).
- Both NixOS modules default to `graphical-session.target`, so either would
  also start under COSMIC; set `systemd.target = "mango-session.target"`.

Trade-off: a shell gives a consistent, GUI-configured desktop close to what
COSMIC offers (control centre, OSD, Bluetooth/Wi-Fi panels) in one package.
The cost is config living in the shell's own settings files (GUI-written,
less declarative), a large fast-moving dependency, and a second single point
of failure next to Mango. The assembled stack is small, every piece has an HM
module, and it is already written.

**Recommendation:** keep the assembled pieces. If the gaps in §§16-18 and §24
annoy in practice, try Noctalia first (no Qt/GTK, both NixOS and HM modules,
explicit Mango support). **Decision:** pieces or shell.

## 6. Launcher

| Launcher | Stars          | Latest release      | Pinned  | HM module        |
|----------|----------------|---------------------|---------|------------------|
| fuzzel   | 972 (Codeberg) | 1.15.0, 2026-09-02  | 1.15.0  | programs.fuzzel  |
| rofi     | 16.5k          | -                   | 2.0.0   | programs.rofi    |
| vicinae  | 10.6k          | -                   | 0.29.2  | programs.vicinae |
| walker   | 3.1k           | v2.17.2, 2026-10-08 | 2.17.2  | services.walker  |
| anyrun   | 1.3k           | -                   | 26.10.0 | programs.anyrun  |
| tofi     | 1.4k           | -                   | 0.9.1   | programs.tofi    |

Sources: [fuzzel][fuzzel], [rofi][rofi], [vicinae][vicinae],
[walker][walker], [anyrun][anyrun], [tofi][tofi].

fuzzel already doubles as the dmenu for cliphist and is one of the pickers
`xdg-desktop-portal-wlr` tries for screencast ([xdg-portals.md][m-portals]).
vicinae (Raycast-style, Qt) is the popular "more than a launcher" option.

**Recommendation:** keep fuzzel. **Decision:** none.

## 7. Notifications

| Daemon | Stars | Latest release      | Pinned | HM module       | Centre / DND |
|--------|-------|---------------------|--------|-----------------|--------------|
| mako   | 3.3k  | v1.11.0, 2026-03-26 | 1.11.0 | services.mako   | no / modes   |
| swaync | 2.6k  | v0.12.6, 2026-03-23 | 0.12.6 | services.swaync | yes / yes    |
| dunst  | 5.6k  | v1.13.2, 2026-03-18 | 1.13.2 | services.dunst  | no / pause   |

Sources: [mako][mako], [swaync][swaync], [dunst][dunst].

COSMIC has a notification history in its panel; mako has none. swaync adds a
slide-out panel with history, do-not-disturb and quick toggles, which waybar
can open (`custom` module).

**Recommendation:** keep mako unless notification history is missed; then
swaync. **Decision:** mako or swaync.

## 8. Lock screen and idle

| Tool     | Stars | Latest release     | Pinned | Module                       |
|----------|-------|--------------------|--------|------------------------------|
| swaylock | 1.2k  | v1.8.6, 2026-07-09 | 1.8.6  | HM programs.swaylock         |
| hyprlock | 1.7k  | v0.9.7, 2026-11-01 | 0.9.7  | HM + NixOS programs.hyprlock |
| gtklock  | 501   | v5.0.1, 2026-11-12 | 4.0.0  | NixOS programs.gtklock       |
| swayidle | 770   | v1.9.1, 2026-10-25 | 1.9.1  | HM services.swayidle         |
| hypridle | 706   | v0.1.8, 2026-07-26 | 0.1.8  | HM services.hypridle         |

Sources: [swaylock][swaylock], [hyprlock][hyprlock], [gtklock][gtklock],
[swayidle][swayidle], [hypridle][hypridle].

Mango provides `ext-session-lock-v1` and `ext-idle-notify-v1`
([`src/main.c`][m-main]), so all of these work. hyprlock looks nicer (blur,
clock widgets) but pulls the Hypr libraries; gtklock's nixpkgs package lags
upstream by a major version. swaylock is the plain, lowest-risk locker.
Lid/suspend behaviour stays with logind and ADR
[0001](adr/0001-suspend-then-hibernate.md); swayidle's `before-sleep` hook
locks first, as the module does now.

**Recommendation:** keep swaylock + swayidle. **Decision:** only if a prettier
lock screen matters (then hyprlock).

## 9. Polkit agent

| Agent           | Stars | Latest release    | Pinned | Module                      |
|-----------------|-------|-------------------|--------|-----------------------------|
| hyprpolkitagent | 233   | 0.2.0, 2026-09-09 | 0.2.0  | HM services.hyprpolkitagent |
| soteria         | 178   | -                 | 0.3.2  | NixOS security.soteria      |
| lxqt-policykit  | -     | -                 | 2.4.0  | HM lxqt-policykit-agent     |
| polkit_gnome    | -     | -                 | 0.105  | HM services.polkit-gnome    |

Sources: [hyprpolkitagent][hpa], [soteria][soteria].

soteria is a small GTK4 agent with a NixOS module that installs and starts it
for every graphical session; it would then also run under COSMIC, which has
its own agent. hyprpolkitagent via HM is already bound to
`mango-session.target` in the module. polkit_gnome's 0.105 is very old.

**Recommendation:** keep hyprpolkitagent. **Decision:** none unless the
hyprtoolkit dependency bothers you.

## 10. Clipboard

| Tool            | Stars | Latest release     | Pinned | HM module                |
|-----------------|-------|--------------------|--------|--------------------------|
| cliphist        | 1.6k  | v0.7.0, 2025-10-11 | 0.7.0  | services.cliphist        |
| wl-clip-persist | 273   | -                  | 0.5.0  | services.wl-clip-persist |
| clipse          | -     | -                  | 1.2.1  | -                        |

Sources: [cliphist][cliphist], [wl-clip-persist][wlcp].

Mango's own docs pair cliphist with `wl-clip-persist` so the clipboard
survives closing the source app ([xdg-portals.md][m-portals]); COSMIC got the
same effect through `COSMIC_DATA_CONTROL_ENABLED`. The module lacks it.

**Recommendation:** keep cliphist; add HM `services.wl-clip-persist` bound to
`mango-session.target`. **Decision:** none.

## 11. Screenshots and screen recording

| Tool                | Stars | Latest release      | Pinned | Module             |
|---------------------|-------|---------------------|--------|--------------------|
| grim + slurp        | -     | -                   | 1.5.0  | -                  |
| satty (annotate)    | 2.5k  | v0.22.0, 2026-08-03 | 0.22.0 | HM programs.satty  |
| swappy (annotate)   | 1.5k  | -                   | 1.8.0  | HM programs.swappy |
| wf-recorder         | 1.3k  | -                   | 0.6.0  | -                  |
| gpu-screen-recorder | -     | -                   | 6.1.6  | -                  |
| wl-screenrec        | -     | -                   | 0.3.2  | -                  |

Sources: [Satty][satty], [swappy][swappy], [wf-recorder][wfrec].

grim uses `wlr-screencopy`/`ext-image-copy-capture`, which Mango has
([`src/main.c`][m-main]). The mango maintainer's own setup uses grim, slurp
and satty ([README][mango]). Recording: wf-recorder for a CLI; OBS or Kooha
through the ScreenCast portal (§12).

**Recommendation:** keep the grim/slurp script; optionally pipe region shots
through satty. **Decision:** whether recording is needed at all.

## 12. xdg-desktop-portal

| Backend                | Stars | Latest release    | Pinned | Role under Mango       |
|------------------------|-------|-------------------|--------|------------------------|
| xdg-desktop-portal-wlr | 744   | 0.9.0, 2026-11-12 | 0.8.5  | ScreenCast, Screenshot |
| xdg-desktop-portal-gtk | -     | -                 | 1.15.3 | FileChooser, Settings  |
| x-d-p-gnome            | -     | -                 | 50.0   | GNOME-only; skip       |
| x-d-p-termfilechooser  | -     | -                 | 1.4.3  | terminal file chooser  |

Sources: [xdpw][xdpw], [mango portal docs][m-portals], nixpkgs
[mango module][nix-mango].

- Mango sets `XDG_CURRENT_DESKTOP=mango` ([`src/main.c`][m-main]), so
  `mango-portals.conf` applies. nixpkgs writes it with `default = gtk`,
  ScreenCast = wlr, Secret = gnome-keyring, Inhibit = gtk, and the misspelled
  ScreenShot key (§2).
- xdpw "has no picker of its own"; it tries slurp, wmenu, wofi, rofi,
  bemenu, mew and fuzzel from `PATH` ([xdg-portals.md][m-portals]). The portal
  runs as a systemd user service, so do not rely on `PATH`: set
  `xdg.portal.wlr.settings.screencast.chooser_cmd` to an absolute slurp or
  fuzzel command.
- Settings (dark/light preference for libadwaita apps) comes from the gtk
  portal, which reads `org.gnome.desktop.interface color-scheme` from dconf.
  Under COSMIC the COSMIC portal answers instead. See §21.

**Recommendation:** keep wlr + gtk; add the Screenshot fix and an explicit
chooser. **Decision:** none.

## 13. XWayland

Mango has built-in XWayland with `xwayland_persistence` and
`xwayland_ignore_scale` options ([miscellaneous.md][m-misc]); the nixpkgs
package exposes `enableXWayland` ([module example][nix-mango]). Mango
recommends `xwayland_ignore_scale=1` plus `Xft.dpi` for fractional scaling,
and positive-only monitor coordinates ([monitors.md][m-monitors]).
xwayland-satellite (0.8.3 pinned) is not needed. **Decision:** none.

## 14. Display / output configuration

| Tool         | Stars        | Latest release    | Pinned | Module                   |
|--------------|--------------|-------------------|--------|--------------------------|
| monitor_rule | (built in)   | -                 | -      | config.conf              |
| kanshi       | 717 (mirror) | -                 | 1.9.0  | HM services.kanshi       |
| shikane      | 154 (mirror) | -                 | 1.1.1  | HM services.shikane      |
| way-displays | 381          | 2.0.1, 2026-11-01 | 1.15.0 | HM services.way-displays |
| wdisplays    | -            | -                 | 1.3.0  | - (GUI)                  |
| nwg-displays | 1.1k         | -                 | 0.5.0  | - (GUI)                  |

Sources: [monitors.md][m-monitors], [kanshi][kanshi] (GitHub mirror,
archived), [shikane][shikane], [way-displays][waydisp],
[nwg-displays][nwgdisp].

Mango's `monitor_rule` matches by name, make, model or serial and is
re-applied on hotplug and reload ([monitors.md][m-monitors]). It implements
`wlr-output-management` ([`src/main.c`][m-main]), so kanshi, shikane,
way-displays, wlr-randr and wdisplays work. nwg-displays only targets sway,
Hyprland and Niri ([repo][nwgdisp]). way-displays in nixpkgs is a major
version behind upstream.

**Recommendation:** `monitor_rule` for the laptop panel; add kanshi only if
the laptop docks to more than one known setup. wdisplays as the ad-hoc GUI.
**Decision:** static rules or kanshi profiles.

## 15. Wallpaper

| Tool      | Stars          | Latest release      | Pinned | HM module          |
|-----------|----------------|---------------------|--------|--------------------|
| swaybg    | -              | -                   | 1.2.2  | -                  |
| awww      | 478 (Codeberg) | v0.12.1, 2026-04-25 | 0.12.1 | services.awww      |
| wpaperd   | 628            | -                   | 1.3.0  | services.wpaperd   |
| hyprpaper | 1.4k           | -                   | 0.8.5  | services.hyprpaper |

Sources: [awww][awww], [swww][swww] (GitHub repo archived; renamed awww on
Codeberg), [wpaperd][wpaperd], [hyprpaper][hyprpaper].

Note Mango's `blur_optimized=1` default blurs against a cached wallpaper
([faq.md][m-faq]); with a flat colour this does not matter.

**Recommendation:** keep `swaybg -c`. awww if image transitions are wanted.
**Decision:** none.

## 16. OSD (volume / brightness)

| Tool    | Stars | Latest release     | Pinned | HM module        |
|---------|-------|--------------------|--------|------------------|
| swayosd | 1.3k  | v0.3.2, 2026-06-22 | 0.3.2  | services.swayosd |
| wob     | -     | -                  | -      | services.wob     |
| avizo   | -     | -                  | -      | services.avizo   |

Sources: [SwayOSD][swayosd].

The module's volume/brightness keys give no visual feedback; COSMIC showed
an OSD. swayosd's `swayosd-client` replaces the `wpctl`/`brightnessctl` calls
and draws the popup itself.

**Recommendation:** swayosd. **Decision:** whether an OSD is wanted.

## 17. Network, Bluetooth and audio

| Need      | Option             | Pinned | Module                             |
|-----------|--------------------|--------|------------------------------------|
| Wi-Fi     | nm-applet (tray)   | 1.36.0 | HM services.network-manager-applet |
| Bluetooth | blueman applet     | 2.4.6  | HM services.blueman-applet         |
| Bluetooth | bluetui (TUI)      | 0.8.2  | -                                  |
| Audio     | pwvucontrol (GTK4) | 0.5.3  | -                                  |
| Audio     | pavucontrol        | 6.2    | -                                  |
| Audio     | wiremix (TUI)      | 0.11.0 | -                                  |

The module has nm-applet and a waybar `wireplumber` module but no Bluetooth
UI and no mixer. COSMIC's panel covered both. pwvucontrol is the native
PipeWire mixer; open it from the waybar `wireplumber` module's `on-click`.

**Recommendation:** add the blueman applet (bound to `mango-session.target`)
and pwvucontrol. **Decision:** GUI or TUI tools.

## 18. Night light

| Tool       | Pinned | HM module           | Works on Mango                 |
|------------|--------|---------------------|--------------------------------|
| wlsunset   | 0.4.0  | services.wlsunset   | yes (`wlr-gamma-control`)      |
| gammastep  | 2.0.11 | services.gammastep  | yes (`wlr-gamma-control`)      |
| hyprsunset | 0.4.0  | services.hyprsunset | Hyprland-only per [repo][hsun] |

Mango creates the gamma-control manager ([`src/main.c`][m-main]).
**Recommendation:** wlsunset if wanted. **Decision:** wanted or not.

## 19. Keyring and secrets

gnome-keyring with the greetd PAM unlock, `gcr-ssh-agent` off, and the
portal's `Secret = gnome-keyring` (nixpkgs mango module) is consistent with
the COSMIC setup and with mango's docs ([xdg-portals.md][m-portals]). The
agent sandbox hides the keyring socket on purpose
([ADR 0004](adr/0004-agent-sandbox-policy.md)); that does not affect the
session. **Decision:** none.

## 20. Login greeter

| Greeter          | Stars | Latest release     | Pinned   | Module / state         |
|------------------|-------|--------------------|----------|------------------------|
| ReGreet          | 839   | 0.5.0, 2026-07-17  | 0.5.0    | NixOS regreet; current |
| tuigreet         | 1.9k  | 0.11.1, 2026-08-20 | 0.11.1   | via `services.greetd`  |
| noctalia-greeter | 588   | none on GitHub     | packaged | NixOS; Noctalia's      |
| dux-greeter      | 54    | 2.1.2, 2026-11-08  | 2.0.0    | NixOS; broken on Mango |
| cosmic-greeter   | -     | -                  | -        | goes when COSMIC goes  |

Sources: [ReGreet][regreet], [tuigreet][tuigreet] (moved to the `tuigreet`
org; `NotAShelf/tuigreet` fork is archived), [noctalia-greeter][noctg],
[dux-greeter][duxg].

ReGreet releases are steady (0.3 → 0.5 in 2026), and it lists every session.
tuigreet is more robust (no compositor needed) and better maintained by
stars, but text-only.

**Recommendation:** keep ReGreet; tuigreet is the fallback. Revisit
noctalia-greeter only if Noctalia is adopted. **Decision:** none.

## 21. Theming (GTK, Qt, cursor, dark mode)

| Need            | Today (COSMIC + Mango)                | After COSMIC            |
|-----------------|---------------------------------------|-------------------------|
| GTK3 dark       | `GTK_THEME=adw-gtk3-dark` from COSMIC | lost; set it in Mango   |
| GTK4/libadwaita | COSMIC portal Settings (COSMIC only)  | dconf `color-scheme`    |
| Qt              | `env=QT_QPA_PLATFORMTHEME,gtk3`       | keep, or HM `qt`        |
| Cursor          | default                               | HM `home.pointerCursor` |

- Under Mango the Settings portal is the gtk one (§12), which reads
  `org/gnome/desktop/interface/color-scheme`. Without
  `dconf.settings."org/gnome/desktop/interface".color-scheme =
  "prefer-dark"`, libadwaita apps will likely render light. Not tested.
- Mango reads `cursor_size` ([default config][m-conf]) and a cursor theme
  from its config struct ([`src/main.c`][m-main]), and exports
  `XCURSOR_THEME`/`XCURSOR_SIZE` to systemd. HM `home.pointerCursor` with
  `gtk.enable` sets the rest.
- [Stylix][stylix] (2.5k stars) would theme everything from one palette, but
  it is a flake, not nixpkgs; excluded by the spec rule. nwg-look (1.2.1) is a
  GUI alternative but writes files HM would own.

**Recommendation:** move `GTK_THEME`, add the dconf `color-scheme` and a
cursor into `modules/mango` before COSMIC is disabled. **Decision:** keep
the plain adw-gtk3 look, or relax the nixpkgs-only rule for Stylix.

## 22. Session and systemd integration

Mango already does what uwsm would: it runs
`dbus-update-activation-environment`, `systemctl --user import-environment`
and starts `mango-session.target`, and stops `graphical-session.target` on
exit ([`src/main.c`][m-main]). The module binds every service to that target.
[uwsm][uwsm] (1.2k stars, pinned 0.27.1, NixOS `programs.uwsm`) would add a
second launcher layer for no gain.

**Recommendation:** no uwsm. **Decision:** none.

## 23. Power / session menu

| Tool    | Stars | Pinned | HM module        |
|---------|-------|--------|------------------|
| wlogout | 1.1k  | 1.2.2  | programs.wlogout |
| wleave  | 347   | 0.7.1  | programs.wleave  |

Sources: [wlogout][wlogout], [wleave][wleave].

Today only `Super+Shift+e` (quit) and `Super+Escape` (lock) exist. A small
`fuzzel --dmenu` script (lock / logout / suspend / reboot / poweroff) reuses
what is installed; wleave is the GTK4 option.

**Recommendation:** fuzzel script. **Decision:** script or wleave.

## 24. Gaps left by leaving COSMIC

| COSMIC piece        | Replacement                                        |
|---------------------|----------------------------------------------------|
| COSMIC Files        | `cosmic-files` 1.11.0 runs standalone; or nautilus |
| COSMIC Settings     | no single app; wdisplays, pwvucontrol, blueman, nm |
| Notification panel  | swaync (§7)                                        |
| OSD                 | swayosd (§16)                                      |
| Night light         | wlsunset (§18)                                     |
| cosmic-pass applet  | Proton Pass full app (research R5)                 |
| Clipboard persist   | wl-clip-persist (§10)                              |
| Dark mode, Qt theme | §21                                                |

The file manager also serves the FileChooser portal only if configured;
under Mango the gtk portal's chooser is used regardless of file manager.

## 25. Risks and open questions

- **Bus factor.** One person writes ~90% of Mango. If they stop, the
  fallback is a migration to niri or sway; keep keybindings in a form that
  ports (the attrset list in `modules/mango` already does).
- **Config churn.** Breaking key renames land in minor releases (§3). Each
  nixpkgs bump may fail the `-p` build check; that is the intended alarm.
- **nixpkgs lag.** waybar (0.15 vs 0.16), mango (0.18.4 vs 0.18.5),
  xdpw (0.8.5 vs 0.9.0), gtklock (4 vs 5), way-displays (1.15 vs 2.0) and
  noctalia (5.4.1 vs 5.5.0) trail upstream by days to months.
- **Portal Screenshot key** (§2): needs a local override and an upstream
  nixpkgs fix. Not yet tested in a running session.
- **libadwaita dark mode** under the gtk portal (§21): expected from how the
  portals divide work, not tested.
- **Mango with ext-workspace in waybar:** works per protocol support; how
  tags beyond the occupied ones appear was not checked.
- **Not verified here:** star counts for projects off GitHub (grim, slurp,
  kanshi upstream on sr.ht, gpu-screen-recorder), and release dates where a
  cell shows `-`. The GitHub unauthenticated API quota ran out mid-research;
  remaining data came through the authenticated GitHub MCP and Codeberg API.

[nix-mango]: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/wayland/mango.nix
[nix-duxg]: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/display-managers/dux-greeter.nix
[nix-dux]: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/wayland/dux-shell.nix
[mango]: https://github.com/mangowm/mango
[mango-rel]: https://github.com/mangowm/mango/releases
[m-contrib]: https://api.github.com/repos/mangowm/mango/contributors
[m-commits]: https://api.github.com/repos/mangowm/mango/commits?since=2026-08-13T00:00:00Z
[m-015]: https://github.com/mangowm/mango/releases/tag/0.15.0
[m-016]: https://github.com/mangowm/mango/releases/tag/0.16.0
[m-017]: https://github.com/mangowm/mango/releases/tag/0.17.0
[m-018]: https://github.com/mangowm/mango/releases/tag/0.18.0
[m-main]: https://github.com/mangowm/mango/blob/main/src/main.c
[m-ext]: https://github.com/mangowm/mango/tree/main/src/ext-protocol
[m-ipc]: https://github.com/mangowm/mango/blob/main/docs/ipc.md
[m-faq]: https://github.com/mangowm/mango/blob/main/docs/faq.md
[m-install]: https://github.com/mangowm/mango/blob/main/docs/installation.md
[m-nixopt]: https://github.com/mangowm/mango/blob/main/docs/nix-options.md
[m-basics]: https://github.com/mangowm/mango/blob/main/docs/configuration/basics.md
[m-misc]: https://github.com/mangowm/mango/blob/main/docs/configuration/miscellaneous.md
[m-monitors]: https://github.com/mangowm/mango/blob/main/docs/configuration/monitors.md
[m-portals]: https://github.com/mangowm/mango/blob/main/docs/configuration/xdg-portals.md
[m-conf]: https://github.com/mangowm/mango/blob/main/assets/config.conf
[niri]: https://github.com/niri-wm/niri
[hypr]: https://github.com/hyprwm/Hyprland
[sway]: https://github.com/swaywm/sway
[river]: https://github.com/riverwm/river
[waybar]: https://github.com/Alexays/Waybar
[wb-016]: https://github.com/Alexays/Waybar/releases/tag/0.16.0
[wb-5078]: https://github.com/Alexays/Waybar/pull/5078
[ironbar]: https://github.com/JakeStanger/ironbar
[ironbar-ws]: https://github.com/JakeStanger/ironbar/wiki/Workspaces
[ironbar-820]: https://github.com/JakeStanger/ironbar/issues/820
[eww]: https://github.com/elkowar/eww
[qs]: https://github.com/quickshell-mirror/quickshell
[ags]: https://github.com/Aylur/ags
[noct]: https://github.com/noctalia-dev/noctalia
[noct-rel]: https://github.com/noctalia-dev/noctalia/releases
[noctg]: https://github.com/noctalia-dev/noctalia-greeter
[dux]: https://github.com/duxlabs-dev/dux-shell
[dux-rel]: https://github.com/duxlabs-dev/dux-shell/releases
[duxg]: https://github.com/duxlabs-dev/dux-greeter
[cael]: https://github.com/caelestia-dots/shell
[end4]: https://github.com/end-4/dots-hyprland
[fuzzel]: https://codeberg.org/dnkl/fuzzel
[rofi]: https://github.com/davatorium/rofi
[vicinae]: https://github.com/vicinaehq/vicinae
[walker]: https://github.com/abenz1267/walker
[anyrun]: https://github.com/anyrun-org/anyrun
[tofi]: https://github.com/philj56/tofi
[mako]: https://github.com/emersion/mako
[swaync]: https://github.com/ErikReider/SwayNotificationCenter
[dunst]: https://github.com/dunst-project/dunst
[swaylock]: https://github.com/swaywm/swaylock
[hyprlock]: https://github.com/hyprwm/hyprlock
[gtklock]: https://github.com/jovanlanik/gtklock
[swayidle]: https://github.com/swaywm/swayidle
[hypridle]: https://github.com/hyprwm/hypridle
[hpa]: https://github.com/hyprwm/hyprpolkitagent
[soteria]: https://github.com/imvaskel/soteria
[cliphist]: https://github.com/sentriz/cliphist
[wlcp]: https://github.com/Linus789/wl-clip-persist
[satty]: https://github.com/Satty-org/Satty
[swappy]: https://github.com/jtheoof/swappy
[wfrec]: https://github.com/ammen99/wf-recorder
[xdpw]: https://github.com/emersion/xdg-desktop-portal-wlr
[kanshi]: https://github.com/emersion/kanshi
[shikane]: https://github.com/hw0lff/shikane
[waydisp]: https://github.com/alex-courtis/way-displays
[nwgdisp]: https://github.com/nwg-piotr/nwg-displays
[awww]: https://codeberg.org/LGFae/awww
[swww]: https://github.com/LGFae/swww
[wpaperd]: https://github.com/danyspin97/wpaperd
[hyprpaper]: https://github.com/hyprwm/hyprpaper
[swayosd]: https://github.com/ErikReider/SwayOSD
[hsun]: https://github.com/hyprwm/hyprsunset
[regreet]: https://github.com/rharish101/ReGreet
[tuigreet]: https://github.com/tuigreet/tuigreet
[stylix]: https://github.com/nix-community/stylix
[uwsm]: https://github.com/Vladimir-csp/uwsm
[wlogout]: https://github.com/ArtsyMacaw/wlogout
[wleave]: https://github.com/AMNatty/wleave
