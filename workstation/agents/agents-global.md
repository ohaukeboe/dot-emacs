# Core Directives

## Environment

- NixOS with flakes. If a program is missing, run it through `nix-shell -p <package> --run '<command>'` rather than installing it or giving up.
- Never `git commit`, `git push`, amend, or force-push without an explicit instruction. Stage the changes, summarize them, then wait.
- Stage and commit in separate Bash calls. First `git add` exactly the files for the commit. Then run `git commit -m ...` alone: no `-a`, no pathspecs, no `git add` chained in. The user reviews the staged diff at the commit prompt, so the commit must contain exactly what is staged. A hook denies commits that break this.
- A commit gate decides each `git commit`. It may prompt, refuse, or open the commit in the user's Emacs for review, where the user can edit the message. A denial saying "The user reviewed and committed this in Emacs as <sha>" means the commit is done: report the sha and do not run `git commit` again. "The user did not commit" means nothing was committed: ask before trying again.
- In a worktree Claude Code created for you (`.claude/worktrees/<name>` on branch `worktree-<name>`) the gate may let a commit through without asking. That is permission to commit your own work there, not to merge or push it.

## Code navigation

- For symbol lookup prefer `lsp-mcp` (`lsp-find-definitions`, `lsp-find-references`, `lsp-workspace-symbols`) or `codebase-memory` (`search_graph`, `trace_path`) over text search.
- For anything about Nix packages, options or versions use the `mcp-nixos` server rather than recalling it — training data lags nixpkgs by months.

## Failure handling

- Do not retry a failed approach unchanged. Say what failed, then change the approach.

## Tables in Markdown and Org files

- Always align table columns: pad cells so every pipe lines up in plain text.
- Keep each table row at most 90 characters wide, the `olivetti-body-width` the user reads these files at. If a table would be wider, shorten cell text, split the table, or use a list instead.

## Sandbox

- Shell commands run in Claude Code's sandbox. Credentials, the container and VM sockets, the main ssh-agent, the keyring and the session bus are hidden on purpose. Project policy cannot lift those.
- When a command fails because of the sandbox (`Read-only file system`, `Operation not permitted`, a blocked host named in the result, or a hidden socket), do not retry it in another form, copy files around it or look for another route. Propose one edit to the project's `.claude/settings.local.json` with the narrowest entry that fixes it, and give a one-line reason. The user approves the diff in the permission prompt.
- Prefer, in this order: `permissions.additionalDirectories` or `sandbox.filesystem.allowWrite`, then `sandbox.network.allowedDomains`, then `sandbox.excludedCommands`. An excluded command runs with the user's full access. End its pattern in ` *`, name the narrowest subcommand, and never an interpreter or a bare tool name.
- If the block is a baseline credential or hidden socket, say so and stop. Exception: a project command that needs containers (Testcontainers tests, `docker compose`). Do not propose exposing a container socket. The sandbox also has its own network namespace, so mapped container ports are unreachable from inside it anyway. Propose excluding the project's narrowest command that needs them, e.g. `"./gradlew test *"`, and say that it runs the project's code with the user's full access.
- `agent-sandbox-probe` checks every protection. Run it when asked to verify the sandbox; it refuses to run outside the sandbox.
- If approvals stop saving or 0-byte files appear under `.claude/`, a killed session left placeholders behind: `claude doctor` lists them.
- `parsing .gitmodules file: ... is locked: Permission denied` from Nix in a repo that has no `.gitmodules` is not a leftover placeholder. The sandbox masks the missing file with a device, which breaks every git-backed flake command, and `claude doctor` does not fix it. Propose committing an empty `.gitmodules`, which keeps the commands sandboxed, before any `excludedCommands` entry.
