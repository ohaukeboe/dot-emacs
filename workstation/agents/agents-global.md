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
