# Quickstart: validate the copy chords

## Prerequisites

- `cosmic-pass` with the four intents pushed, `flake.lock` bumped, the
  laptop deployed (`sudo nixos-rebuild switch --flake .#laptop`), a Mango
  session, a signed-in `pass-cli`.
- A test item with a username, a one-time code and a website; a second item
  without username, email, code or website (a note will do).

## Gates

```bash
# in ~/projects/cosmic-pass
just check
# here
nix fmt && nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
just qs-check
```

## Scenarios

| #   | Do                                                 | Expect                 |
|-----|----------------------------------------------------|------------------------|
| K1  | type the test item, `Ctrl+U`, paste                | username; popup closed |
| K2  | same, `Ctrl+O`, paste                              | code matches the app   |
| K3  | same, `Ctrl+L`, paste                              | first website          |
| K4  | `Tab`, highlight Password, `Ctrl+U`                | username; closed       |
| K5  | note item: `Ctrl+U`, `Ctrl+O`, `Ctrl+L`            | notice; still open     |
| K6  | empty query: `Right`, `Left`, `Right`, `Shift+Tab` | open, back, open, back |
| K7  | type `ab`, `Left`, `Right`                         | only the cursor moves  |
| K8  | many fields, reveal one, `PageDown`                | page jump; masked      |
| K9  | `Ctrl+J`, `Ctrl+K`                                 | nothing                |
| K10 | lock session, open, unlock, `Ctrl+Shift+R`         | items appear           |
| K11 | signed in: `Ctrl+Shift+R`, `Ctrl+Shift+S`          | nothing                |
| K12 | after K1–K3, open clipboard history                | no copied value        |
