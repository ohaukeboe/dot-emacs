# Quickstart: validating Agent Context Hygiene

## Build-time checks (no deploy needed)

```bash
git add -A specs/007-context-hygiene workstation tests   # flake sees tracked files only
nix fmt                                                  # then revert unrelated churn
nix flake check                                          # runs both new checks below
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
for h in work-laptop desktop laptop dig-laptop; do
  nix build ".#nixosConfigurations.$h.config.system.build.toplevel" --no-link
done
```

`nix flake check` must include these two checks:

- `context-statusline`: covers every input row in
  [contracts/statusline.md](contracts/statusline.md).
- `rtk-banner`: the canary prints the banner without the variable, and
  nothing prints with it.

Inspect the generated settings against
[contracts/deployed-settings.md](contracts/deployed-settings.md):

```bash
s=$(find -L result/home-files/.claude -maxdepth 1 -name settings.json)
jq '{statusLine, autoCompactWindow, autoMemoryEnabled, env,
     deny: .permissions.deny, skillOverrides,
     budget: .skillListingBudgetFraction, enabledPlugins}' "$s"
```

**Expected:** each key matches the contract.
`env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` and `budget` are `null`.

Also try invalid values. Each must fail evaluation with a message that names
the file:

- `agents.context.warnTokens = 500000` (larger than `strongTokens`)
- `agents.context.autoCompactTokens = 50000`
- a `skillOverrides` value of `"hidden"`

## After `sudo nixos-rebuild switch --flake .#<host>`

Run these in a new Claude Code session in this repository.

| #   | Do                                   | Expect                                 |
|-----|--------------------------------------|----------------------------------------|
| Q1  | Send a prompt; read status line      | badge + dim size, e.g. `[CAVEMAN] 41K` |
| Q2  | Agent runs `ls`                      | no banner; output compressed           |
| Q3  | `/autocompact 300k`, then `/context` | 300K for this session; no error        |
| Q4  | `/mcp`                               | no `mobile-mcp` or `chrome-devtools`   |
| Q5  | `/doctor`; `claude --debug` log      | no listing over-budget warning         |
| Q6  | `/skills`                            | `punkt-*`, `understand*` user-only     |
| Q7  | Extract a long page via kagi         | file path + preview, not full text     |
| Q8  | Ask for a todo list                  | it uses `bd`; no Task* tools offered   |

**Q6 note:** the cavekit skills (`spec`, `build`, `check`, `backprop`) appear
by name only. The `speckit-*` skills appear unchanged.

### Handoff round trip (US2, SC-002)

1. Claim a scratch bead: `bd create --title="handoff test" --type=task`, then
   `bd update <id> --claim`.
2. Run `/bead-handoff`. Expect `Note saved to <id>. You can now run /clear.`
3. Run `bd show <id>`. Expect a `Handoff YYYY-MM-DD` note with `Tried:`,
   `Failed:` and `Next:` lines. The status must still be `in_progress`.
4. Run `/clear`, then ask "what was I doing?". The answer must cite the note.
   Time it: the whole round trip must take under 2 minutes.
5. Close the scratch bead.

### Per-repository opt-in (US6)

1. In another repository, add `{"enabledPlugins": {"hm-browser@skills-dir":
   true}}` to `.claude/settings.local.json`.
2. Start a session there and run `/mcp`. `chrome-devtools` must be
   connected. Back in this repository, it must still be absent.
3. If the plugin is not picked up after switching, check `claude plugin list`
   (see research R6/R7 on plugin cache refresh).
