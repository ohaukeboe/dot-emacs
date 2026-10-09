# Contract: project policy file

Path: `<project>/.claude/settings.local.json`, which is personal and globally
gitignored, or `<project>/.claude/settings.json`, which is committed. The
schema is Claude Code's settings schema. This contract lists the subset a
project policy uses.

```json
{
  "permissions": {
    "additionalDirectories": ["~/projects/sibling"]
  },
  "sandbox": {
    "filesystem": {
      "allowWrite": ["~/.cache/some-tool"],
      "allowRead":  ["~/projects/readonly-sibling"]
    },
    "network": { "allowedDomains": ["registry.npmjs.org"] },
    "excludedCommands": ["docker compose *"]
  }
}
```

## Rules

- Project policy only widens access. It cannot narrow the baseline below the
  floor, and the floor's credential denies and strict mode cannot be removed.
- Prefer, in this order: `additionalDirectories` or `filesystem.allowWrite`,
  then `network.allowedDomains`, then `excludedCommands`. Use
  `excludedCommands` last, because a matching command runs with full user
  access (classifier-reviewed in auto mode).
- `excludedCommands` patterns end in ` *` and name the narrowest subcommand.
  Never use an interpreter or a bare tool name.
- Every change is made with the Edit tool and gets a permission prompt.

## Agent behaviour on a sandbox failure (`agents-global.md`)

1. Recognise the failure: `Read-only file system`, `Operation not permitted`,
   a blocked host named in the tool result, or `connect: No such file or
   directory` for a hidden socket.
2. Do not retry in another form, do not copy files to work around the block,
   and do not ask for an unconfined run.
3. Propose one Edit to the project policy with the narrowest entry, and give a
   one-line reason in the reply.
4. If the block is a baseline credential or hidden service, say so and stop.
   Project policy cannot lift it.

## Reference profiles

| Project | Policy |
|---|---|
| default | none |
| dot-emacs | `additionalDirectories: ["~/Nextcloud/org_notes"]`, `allowedDomains: ["search.nixos.org"]` |
| needs a sibling, read-write | `additionalDirectories: ["~/projects/<sibling>"]` |
| needs Docker | `excludedCommands: ["docker compose *"]` |
| runs a VM directly from the shell | `excludedCommands: ["./result/bin/run-*-vm"]` (only if the quickstart shows no `/dev/kvm` in the sandbox) |
