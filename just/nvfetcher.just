# Source management with nvfetcher
# Version-pinned external sources live in nvfetcher.toml and are generated
# into _sources/generated.nix, consumed via the pkgs.nvSources overlay.

# Uses a gh-auth token keyfile to avoid GitHub's low anonymous rate limit (403s on CheckGitHubTag/Release).
# Regenerate _sources/ from nvfetcher.toml (nodejs is needed for the npm `src.cmd` entries)
update-sources:
    #!/usr/bin/env bash
    set -euo pipefail
    keyfile=$(mktemp)
    trap 'rm -f "$keyfile"' EXIT
    printf '[keys]\ngithub = "%s"\n' "$(gh auth token)" > "$keyfile"
    chmod 600 "$keyfile"
    nix-shell -p nvfetcher nodejs --run "nvfetcher -c nvfetcher.toml -o _sources -k $keyfile"

# Build this host and rewrite every stale fixed-output hash (vendorHash, npmDepsHash, ...) nix reports
fix-hashes host=`hostname`:
    #!/usr/bin/env bash
    set -uo pipefail
    log=$(mktemp)
    trap 'rm -f "$log"' EXIT
    # A fixed hash can unblock a build that then reveals the next stale one.
    for _ in 1 2 3; do
        nix build --no-link --keep-going ".#nixosConfigurations.{{host}}.config.system.build.toplevel" 2>&1 | tee "$log"
        status=${PIPESTATUS[0]}
        [ "$status" -eq 0 ] && exit 0
        pairs=$(awk '/specified:/ {old=$2} /got:/ && old {print old, $2; old=""}' "$log")
        [ -z "$pairs" ] && exit "$status"
        while read -r old new; do
            files=$(git grep -lF "$old" -- '*.nix' ':(exclude)_sources')
            [ -z "$files" ] && { echo "fix-hashes: $old not found in any .nix file" >&2; exit 1; }
            echo "fix-hashes: $old -> $new in" $files
            sed -i "s|$old|$new|g" $files
        done <<< "$pairs"
    done
    exit 1
