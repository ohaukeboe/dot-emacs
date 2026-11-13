# Feature Specification: Mango Window Manager Session

**Feature Branch**: `010-mango-wm-session`

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "I wan't to try using a wm instead of a de. So
make another nix module for using mangowm and enable it for laptop. Always
prefer to use packages from nixpkgs"

## Clarifications

### Session 2026-11-11

- Q: Does Mango run alongside COSMIC on `laptop` or replace it? → A: Mango is
  meant to replace COSMIC eventually. The Mango module brings its own login
  screen, which replaces COSMIC's on `laptop`; COSMIC stays installed and
  selectable as a session from that login screen.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Log in to a Mango session on the laptop (Priority: P1)

The user wants to try a standalone tiling window manager (Mango) instead of a
full desktop environment, and later replace COSMIC with it. On the `laptop`
machine a login screen that belongs to the Mango setup starts Mango by default,
and they land in a working tiled desktop where they can open a terminal and
an application launcher, move and resize windows by keyboard, switch
workspaces, and log out.

**Why this priority**: Without a session that starts and can launch programs,
nothing else in this feature has value.

**Independent Test**: Deploy the `laptop` configuration, choose Mango at the
login screen, open a terminal and a launcher by keyboard, tile two windows,
switch workspace, log out.

**Acceptance Scenarios**:

1. **Given** the `laptop` configuration is deployed, **When** the user reaches
   the login screen, **Then** it is the Mango module's login screen, not
   COSMIC's, and Mango is the preselected session.
2. **Given** the user logged in to Mango, **When** they press the terminal and
   launcher shortcuts, **Then** a terminal and an application launcher open.
3. **Given** a Mango session, **When** the user chooses log out, **Then** they
   return to the login screen without a reboot.

---

### User Story 2 - Daily-use essentials work in Mango (Priority: P2)

Inside Mango the user keeps the everyday functions the desktop environment
gave them: a status bar (workspaces, clock, battery, network, audio),
notifications, screen locking and idle lock, volume/brightness keys, the same
keyboard layout and touchpad behaviour, screenshots, screen sharing in the
browser, the secret store their tools rely on, and the password quick-access
shortcuts.

**Why this priority**: A session that starts but lacks these is not usable for
a real day of work, so the trial would not be fair.

**Independent Test**: In a Mango session, check each listed function once:
lock the screen, take a screenshot, share a screen in a browser call, change
volume and brightness by key, receive a notification, sign a git commit, open
the password popup.

**Acceptance Scenarios**:

1. **Given** a Mango session, **When** the user is idle past the lock timeout
   or presses the lock shortcut, **Then** the screen locks and needs the
   password to unlock.
2. **Given** a Mango session, **When** the user starts screen sharing in a
   browser, **Then** they can pick a screen or window and it is shared.
3. **Given** a Mango session, **When** the user types, **Then** the EU layout
   with Caps Lock as Ctrl applies, and the touchpad uses tap-to-click and
   natural scrolling, as in the COSMIC setup.
4. **Given** a Mango session, **When** the user signs a git commit, **Then**
   the SSH agent used for signing is the Home Manager agent, not one started
   by the session.
5. **Given** a Mango session, **When** the laptop lid closes or it idles long
   enough, **Then** it suspends and later hibernates as it does today.

---

### User Story 3 - Fall back to COSMIC at any time (Priority: P3)

The user is only trying Mango. If it does not suit them on a given day they pick COSMIC at the Mango login screen and get their existing desktop
unchanged. If they drop the trial, turning the Mango toggle off removes it
fully and COSMIC's own login screen returns. When they commit to Mango,
turning COSMIC off leaves a complete system with Mango and its login screen.

**Why this priority**: A trial is only low-risk if leaving it is one login
choice or one toggle away.

**Independent Test**: On the deployed `laptop`, pick COSMIC on the Mango login
screen and confirm it behaves as before. Separately, evaluate `laptop` with the Mango toggle off
and confirm its system closure no longer contains Mango or its tools.

**Acceptance Scenarios**:

1. **Given** both sessions installed, **When** the user picks COSMIC on the
   Mango login screen, **Then** COSMIC starts with its current settings,
   panel and shortcuts.
2. **Given** the Mango toggle is off on a machine, **When** the configuration
   is evaluated, **Then** no Mango package, configuration file or service is
   part of it, and COSMIC's own login screen is back if COSMIC is on.
3. **Given** Mango on and COSMIC off, **When** the configuration is evaluated
   and deployed, **Then** the machine boots to the Mango login screen and
   Mango starts, with no COSMIC component required.
4. **Given** the other machines (`desktop`, `work-laptop`, `dig-laptop`),
   **When** they are evaluated, **Then** their configuration is unchanged.

### Edge Cases

- Two modules each want to own the login screen: when Mango's login screen is
  on, COSMIC's must be off, and evaluation must fail with a clear message if
  both are configured to run.
- The last session used was COSMIC: the login screen should remember it or
  default to Mango; either is fine, but it must never offer no session.

- Mango is enabled on a machine that does not also run a desktop environment:
  the session must still bring up its own portal, secret store and polkit
  agent rather than relying on COSMIC to provide them.
- Both COSMIC and Mango are enabled: the two must not fight over which
  desktop portal, Qt theme or session variables apply; each session uses its
  own.
- An external monitor is plugged in or removed while in Mango: windows move to
  the remaining output and the bar follows.
- The Mango config file has an error: the session should still start with
  usable defaults rather than leave the user at a black screen.
- A needed tool is not packaged in nixpkgs: it is left out and noted, rather
  than pulled from an outside source, unless the user asks for it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The configuration MUST provide a separate toggleable module for
  a Mango window manager session, off by default.
- **FR-002**: The `laptop` machine MUST enable that module; no other machine's
  configuration may change.
- **FR-003**: The Mango module MUST provide its own login screen, built only
  from nixpkgs, that lists every installed session (Mango and, when enabled,
  COSMIC) with Mango as the default.
- **FR-003a**: On `laptop`, the Mango login screen MUST replace COSMIC's.
  The COSMIC module MUST let its login screen be turned off without turning
  off the COSMIC session, through a declared option.
- **FR-003b**: Evaluation MUST fail with a message naming the fix if two login
  screens are enabled at once.
- **FR-004**: The Mango session MUST provide: terminal and launcher
  shortcuts, keyboard window tiling and workspace switching, a status bar,
  notifications, screen lock with idle lock, a polkit authentication agent,
  screenshots, media/brightness keys, and clipboard history.
- **FR-005**: The Mango session MUST apply the same keyboard layout, Caps Lock
  remap, key repeat and touchpad behaviour as the COSMIC module.
- **FR-006**: The Mango session MUST support screen sharing and file pickers
  for sandboxed and browser applications.
- **FR-007**: The Mango session MUST keep the existing SSH agent for git
  signing and MUST NOT start a competing one.
- **FR-008**: The Mango session MUST provide the password quick-access
  shortcuts the COSMIC module provides (Proton Pass, 1Password).
- **FR-009**: Every package the module installs MUST come from nixpkgs. A
  component not in nixpkgs MUST be omitted, or replaced by a nixpkgs
  alternative, and the gap recorded.
- **FR-010**: With the module disabled, it MUST contribute nothing to a
  machine's configuration.
- **FR-011**: Enabling the module MUST NOT change the COSMIC session's
  behaviour on the same machine, other than which login screen starts it.
- **FR-014**: The Mango module MUST NOT depend on the COSMIC module being on;
  with COSMIC off it alone yields a complete graphical system.
- **FR-012**: The module's settings that change per machine or per taste
  (for example terminal, launcher, lock timeout) MUST be declared as typed
  options with defaults, so a mistake fails at evaluation.
- **FR-013**: Mango's own configuration MUST be generated from this
  repository so a fresh install comes up identical, with no manual
  post-install steps.

### Key Entities

- **Mango module**: the toggle that turns the window manager session on for a
  machine, with its options (terminal, launcher, lock timeout).
- **Session components**: the bar, launcher, notification daemon, locker,
  idle handler, polkit agent, portal and clipboard manager that together make
  the window manager usable day to day.
- **Login screen**: the greeter the Mango module owns; lists the installed
  sessions and starts the chosen one.
- **Machine composition**: the `laptop` entry in the machine registry that
  enables the module next to COSMIC, with COSMIC's login screen off.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After one deploy, the user logs in to Mango on `laptop` and
  opens a terminal within 10 seconds of the login screen.
- **SC-002**: All 8 daily functions in User Story 2 work in a Mango session on
  the first try, with no manual setup after deploy.
- **SC-003**: Switching between Mango and COSMIC needs only a log out and a
  choice at the Mango login screen; zero configuration changes.
- **SC-007**: Dropping COSMIC later is a one-line toggle change on `laptop`
  that evaluates and boots to a working Mango login.
- **SC-004**: Turning the toggle off removes 100% of the module's packages and
  files from the machine on the next deploy.
- **SC-005**: The configurations of the other three machines evaluate to the
  same result before and after the change.
- **SC-006**: Zero packages installed by the module come from outside nixpkgs.

## Assumptions

- "laptop" means the machine registered as `laptop` in the machine registry,
  not every laptop.
- Mango is meant to replace COSMIC. For now both are installed on `laptop`;
  the Mango module's login screen replaces COSMIC's and offers both sessions.
- nixpkgs ships greeters that can run inside Mango (for example the
  `dux-greeter` option, which lists `mangowc` as a supported compositor); the
  exact greeter is chosen in planning, from nixpkgs only.
- "Mango" / "mangowm" is the dwl-based Wayland compositor that nixpkgs ships
  as `mangowc` with a NixOS `programs.mango` option; that option is preferred
  over an outside flake.
- Look and feel follows the COSMIC setup where cheap: dark background,
  24-hour clock, thin top bar. Pixel-level matching is out of scope.
- Default terminal is the one the user already uses; default launcher, bar,
  notifier, locker and idle handler are common nixpkgs choices for wlroots
  compositors, settled in planning.
- Suspend-then-hibernate, secure boot and other `laptop` modules work the same
  under either session, since they do not depend on the desktop.
- Home Manager has no Mango module; its configuration file is written by this
  repository directly.
