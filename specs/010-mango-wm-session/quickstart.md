# Quickstart: validate the Mango session

## 1. Evaluation and build (no deploy)

```bash
git add modules/mango specs/010-mango-wm-session
nix fmt            # revert unrelated churn afterwards
nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
```

Expected: both pass. The build includes the `mango -c … -p` config check.

## 2. Other machines unchanged (SC-005)

Comparing against a git rev does not work: the git-agecrypt files under
`private/` are encrypted in git. Stash the change instead, and skip the eval
cache, which otherwise returns stale results:

```bash
drv() { nix eval --no-eval-cache --raw ".#nixosConfigurations.$1.config.system.build.toplevel.drvPath"; }
git stash push --include-untracked -q -- modules machines
for h in desktop work-laptop dig-laptop; do echo "$h $(drv $h)"; done > $TMPDIR/before
git stash pop --index -q
for h in desktop work-laptop dig-laptop; do echo "$h $(drv $h)"; done | diff $TMPDIR/before - && echo unchanged
```

Expected: `unchanged`.

## 3. Guards fire (FR-003b, FR-010)

- Set `modules.cosmic-de.greeter.enable = true` on `laptop` and evaluate:
  expect the assertion naming `modules.cosmic-de.greeter.enable = false`.
- Set `modules.mango.enable = false` on `laptop` and build: expect no `mango`,
  `regreet`, `waybar` in `nix path-info -r` of the toplevel.
- Set `modules.cosmic-de.enable = false` (Mango on) and build: expect success
  (SC-007).

## 4. On the laptop (manual, after `sudo nixos-rebuild switch --flake .#laptop`)

| Check                                                | Spec        |
|------------------------------------------------------|-------------|
| ReGreet login shows; sessions list Mango and COSMIC  | FR-003      |
| Mango: Super+Return terminal, Super+d launcher       | US1, SC-001 |
| Bar shows tags, clock, battery, network, audio       | US2         |
| `notify-send hi` shows a notification                | US2         |
| Super+Escape locks; screen locks before suspend      | US2         |
| Volume and brightness keys work                      | US2         |
| Print / Shift+Print save screenshots                 | US2         |
| Browser screen share lists screens/windows           | FR-006      |
| `$SSH_AUTH_SOCK` is the HM agent; signed commit      | FR-007      |
| Super+Space / Super+Shift+Space open password apps   | FR-008      |
| Lid close suspends, later hibernates                 | US2         |
| Super+Shift+e returns to ReGreet; pick COSMIC works  | US3, SC-003 |
| In COSMIC, no Mango session service runs (T030)      | FR-011      |
