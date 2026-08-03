# Source management with nvfetcher
# Version-pinned external sources live in nvfetcher.toml and are generated
# into _sources/generated.nix, consumed via the pkgs.nvSources overlay.

# Regenerate _sources/ from nvfetcher.toml (nodejs is needed for the npm `src.cmd` entries)
# Uses a gh-auth token keyfile to avoid GitHub's low anonymous rate limit (403s on CheckGitHubTag/Release).
update-sources:
    #!/usr/bin/env bash
    set -euo pipefail
    keyfile=$(mktemp)
    trap 'rm -f "$keyfile"' EXIT
    printf '[keys]\ngithub = "%s"\n' "$(gh auth token)" > "$keyfile"
    chmod 600 "$keyfile"
    nix-shell -p nvfetcher nodejs --run "nvfetcher -c nvfetcher.toml -o _sources -k $keyfile"
