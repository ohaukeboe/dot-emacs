# Core Directives

## Environment

- NixOS with flakes. If a program is missing, run it through `nix-shell -p <package> --run '<command>'` rather than installing it or giving up.
- Never `git commit`, `git push`, amend, or force-push without an explicit instruction. Stage the changes, summarize them, then wait.
- Stage and commit in separate Bash calls. First `git add` exactly the files for the commit. Then run `git commit -m ...` alone: no `-a`, no pathspecs, no `git add` chained in. The user reviews the staged diff at the commit prompt, so the commit must contain exactly what is staged. A hook denies commits that break this.

## Code navigation

- For symbol lookup prefer `lsp-mcp` (`lsp-find-definitions`, `lsp-find-references`, `lsp-workspace-symbols`) or `codebase-memory` (`search_graph`, `trace_path`) over text search.
- For anything about Nix packages, options or versions use the `mcp-nixos` server rather than recalling it — training data lags nixpkgs by months.

## Failure handling

- Do not retry a failed approach unchanged. Say what failed, then change the approach.

## Sandbox

- Shell commands run in Claude Code's sandbox. Credentials, the container and VM sockets, the main ssh-agent, the keyring and the session bus are hidden on purpose. Project policy cannot lift those.
- When a command fails because of the sandbox (`Read-only file system`, `Operation not permitted`, a blocked host named in the result, or a hidden socket), do not retry it in another form, copy files around it or look for another route. Propose one edit to the project's `.claude/settings.local.json` with the narrowest entry that fixes it, and give a one-line reason. The user approves the diff in the permission prompt.
- Prefer, in this order: `permissions.additionalDirectories` or `sandbox.filesystem.allowWrite`, then `sandbox.network.allowedDomains`, then `sandbox.excludedCommands`. An excluded command runs with the user's full access. End its pattern in ` *`, name the narrowest subcommand, and never an interpreter or a bare tool name.
- If the block is a baseline credential or hidden socket, say so and stop.
- `agent-sandbox-probe` checks every protection. Run it when asked to verify the sandbox; it refuses to run outside the sandbox.
- If approvals stop saving or 0-byte files appear under `.claude/`, a killed session left placeholders behind: `claude doctor` lists them.
- `parsing .gitmodules file: ... is locked: Permission denied` from Nix in a repo that has no `.gitmodules` is not a leftover placeholder. The sandbox masks the missing file with a device, which breaks every git-backed flake command, and `claude doctor` does not fix it. Propose committing an empty `.gitmodules`, which keeps the commands sandboxed, before any `excludedCommands` entry.
